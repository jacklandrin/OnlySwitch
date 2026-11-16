//
//  Updater.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/12.
//

import AppKit
import Extensions
import OSLog
import Sparkle

/// A newer build published in the Sparkle appcast.
struct AvailableUpdate: Equatable, Sendable {
    /// The appcast `sparkle:version`, which is the app's build number (`CFBundleVersion`).
    let build: String
    /// The appcast `sparkle:shortVersionString`, e.g. "3.6.0".
    let displayVersion: String

    var displayText: String {
        displayVersion == build ? build : "\(displayVersion) (\(build))"
    }
}

enum UpdateProbeResult: Equatable, Sendable {
    case available(AvailableUpdate)
    case upToDate
    /// Another Sparkle session (for example the update window) is already running.
    case busy
    case failed
}

/// Wraps Sparkle. Sparkle compares the appcast `sparkle:version` with the bundle's
/// `CFBundleVersion`, so updates are detected by build number rather than marketing version.
@MainActor
final class Updater {
    static let shared = Updater()

    private let delegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController
    private var probeContinuations: [CheckedContinuation<UpdateProbeResult, Never>] = []
    private var probeTimeoutTask: Task<Void, Never>?
    private var showWindowAfterProbe = false

    /// Safety net in case Sparkle never reports the end of a probe.
    private static let probeTimeout: Duration = .seconds(60)

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        delegate.onProbeFinished = { [weak self] result in
            self?.finishProbe(with: result)
        }
    }

    /// Shows Sparkle's update window in front of other apps.
    nonisolated static func checkForUpdates() {
        Task { @MainActor in
            shared.showUpdateWindow()
        }
    }

    func showUpdateWindow() {
        // Sparkle ignores `checkForUpdates` while a probe session runs; show it once the probe ends.
        guard probeContinuations.isEmpty else {
            showWindowAfterProbe = true
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    /// Silently checks the appcast without showing any UI. Skipped builds are not reported.
    func probeForUpdate() async -> UpdateProbeResult {
        let updater = updaterController.updater
        if probeContinuations.isEmpty {
            // Sparkle silently ignores the request when the updater failed to start or is busy.
            guard updater.canCheckForUpdates else {
                return updater.sessionInProgress ? .busy : .failed
            }
        }
        return await withCheckedContinuation { continuation in
            probeContinuations.append(continuation)
            guard probeContinuations.count == 1 else { return }
            updater.checkForUpdateInformation()
            probeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.probeTimeout)
                guard !Task.isCancelled else { return }
                Logger.app.error("Update check timed out")
                self?.finishProbe(with: .failed)
            }
        }
    }

    private func finishProbe(with result: UpdateProbeResult) {
        probeTimeoutTask?.cancel()
        probeTimeoutTask = nil
        let continuations = probeContinuations
        probeContinuations.removeAll()
        continuations.forEach { $0.resume(returning: result) }

        guard showWindowAfterProbe else { return }
        showWindowAfterProbe = false
        // Let Sparkle finish tearing down the probe session first.
        DispatchQueue.main.async { [weak self] in
            self?.showUpdateWindow()
        }
    }
}

@MainActor
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var onProbeFinished: ((UpdateProbeResult) -> Void)?
    private var foundUpdate: AvailableUpdate?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundUpdate = AvailableUpdate(build: item.versionString, displayVersion: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let found = foundUpdate
        foundUpdate = nil
        guard updateCheck == .updateInformation else { return }

        if let found {
            onProbeFinished?(.available(found))
        } else if let error = error as NSError?,
                  !(error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)) {
            Logger.app.error("Update check failed: \(error.localizedDescription)")
            onProbeFinished?(.failed)
        } else {
            onProbeFinished?(.upToDate)
        }
    }
}
