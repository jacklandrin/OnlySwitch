import AppKit
import Dependencies
import Extensions
import Foundation

@MainActor
struct CrashReportWatermark {
    private static let cutoffKey = "onlySwitchCrashReportCutoffDate"
    let defaults: UserDefaults

    var cutoff: Date? { defaults.object(forKey: Self.cutoffKey) as? Date }

    func beginMonitoring(at date: Date) {
        if cutoff == nil {
            defaults.set(date, forKey: Self.cutoffKey)
        }
    }

    func acknowledge(_ date: Date) {
        guard let cutoff, date > cutoff else { return }
        defaults.set(date, forKey: Self.cutoffKey)
    }
}

struct CrashReportClient: Sendable, DependencyKey {
    var beginMonitoring: @MainActor @Sendable () -> Void
    var cutoff: @MainActor @Sendable () -> Date?
    var latest: @Sendable (Date) async -> CrashReportDiscovery.Report?
    var present: @MainActor @Sendable () -> Bool
    var acknowledge: @MainActor @Sendable (Date) -> Void
    var reveal: @MainActor @Sendable (URL) -> Void

    private static let scanQueue = DispatchQueue(label: "OnlySwitch.CrashReportDiscovery", qos: .utility)

    static let liveValue = Self(
        beginMonitoring: { CrashReportWatermark(defaults: .standard).beginMonitoring(at: Date()) },
        cutoff: { CrashReportWatermark(defaults: .standard).cutoff },
        latest: { cutoff in
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
            return await withCheckedContinuation { continuation in
                // Directory and file reads are synchronous; keep them off the UI and cooperative executors.
                scanQueue.async {
                    continuation.resume(returning: CrashReportDiscovery.latest(
                        in: directory, bundleIdentifier: bundleIdentifier, after: cutoff, through: Date()
                    ))
                }
            }
        },
        present: {
            let alert = NSAlert()
            alert.messageText = "OnlySwitch crash report available".localized()
            alert.informativeText = "macOS saved a crash report for OnlySwitch. You can find it in Finder if you want to share it when reporting the problem.".localized()
            alert.addButton(withTitle: "OK".localized())
            alert.addButton(withTitle: "Show in Finder".localized())
            NSApp.activate()
            return alert.runModal() == .alertSecondButtonReturn
        },
        acknowledge: { CrashReportWatermark(defaults: .standard).acknowledge($0) },
        reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    )

    static let testValue = Self(
        beginMonitoring: {}, cutoff: { nil }, latest: { _ in nil }, present: { false }, acknowledge: { _ in }, reveal: { _ in }
    )
}

extension DependencyValues {
    var crashReport: CrashReportClient {
        get { self[CrashReportClient.self] }
        set { self[CrashReportClient.self] = newValue }
    }
}

@MainActor
final class CrashReportPrompt {
    @Dependency(\.crashReport) private var client

    static let isRunningTests = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestBundleInjectPath"] != nil
    }()

    static func beginMonitoring() {
        guard !isRunningTests else { return }
        @Dependency(\.crashReport) var client
        client.beginMonitoring()
    }

    func presentIfNeeded() async -> Bool {
        guard let cutoff = client.cutoff(),
              let report = await client.latest(cutoff), !Task.isCancelled else { return false }

        let shouldReveal = client.present()
        client.acknowledge(report.timestamp)
        if shouldReveal {
            client.reveal(report.url)
        }
        return true
    }
}
