//
//  BrightnessSyncManager.swift
//  OnlySwitch
//
//  Keeps external monitors in lock-step with the built-in display's brightness.
//
//  Screen changes and the Dim Screen switch trigger an immediate refresh. A
//  low-frequency poll also catches brightness keys, ambient light, and Control
//  Center changes that macOS does not publish as notifications. At the built-in
//  panel's minimum external monitors are switched fully off (DPMS).
//

import Foundation
import AppKit
import Combine
import Defines

struct BrightnessSyncState {
    private(set) var isRunning = false
    private(set) var topologyGeneration: UInt64 = 0
    private(set) var hasBuiltInDisplay = false
    private(set) var externalDisplayCount = 0

    var shouldPoll: Bool {
        isRunning && hasBuiltInDisplay && externalDisplayCount > 0
    }

    mutating func start() {
        isRunning = true
    }

    mutating func stop() {
        isRunning = false
        externalDisplayCount = 0
        topologyGeneration &+= 1
    }

    mutating func topologyChanged(hasBuiltInDisplay: Bool) -> UInt64 {
        self.hasBuiltInDisplay = hasBuiltInDisplay
        externalDisplayCount = 0
        topologyGeneration &+= 1
        return topologyGeneration
    }

    @discardableResult
    mutating func acceptRefresh(generation: UInt64, externalDisplayCount: Int) -> Bool {
        guard isRunning, generation == topologyGeneration else { return false }
        self.externalDisplayCount = externalDisplayCount
        return true
    }
}

@MainActor
final class BrightnessSyncManager {
    static let shared = BrightnessSyncManager()

    private let displayManager = DisplayManager()
    private var timerCancellable: AnyCancellable?
    private var wakeSyncTask: Task<Void, Never>?
    private var lastSyncedBrightness: Float = -1
    private var externalsPoweredOff = false
    private var state = BrightnessSyncState()

    /// Smallest built-in brightness change worth mirroring (~0.4%). Filters out
    /// floating-point noise while still catching a single F1/F2 key press.
    private let changeThreshold: Float = 0.004

    /// At/below this built-in level the external monitors are switched fully off
    /// via DDC power control (DPMS), so they go dark together with the built-in
    /// panel at its minimum instead of staying on at their lowest backlight.
    private let powerOffThreshold: Float = 0.01

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(builtInBrightnessChanged),
            name: .builtInDisplayBrightnessDidChange,
            object: nil
        )
    }

    /// Starts or stops syncing according to the user's preference.
    func updateState() {
        if Preferences.shared.syncExternalBrightness {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !state.isRunning else { return }
        state.start()
        lastSyncedBrightness = -1
        refreshDisplayTopology()
    }

    private func stop() {
        guard state.isRunning else { return }
        state.stop()
        timerCancellable?.cancel()
        timerCancellable = nil
        wakeSyncTask?.cancel()
        wakeSyncTask = nil
        // Don't leave external monitors stuck in DPMS off when syncing is disabled.
        if externalsPoweredOff {
            externalsPoweredOff = false
            ExternalDisplayManager.shared.setPower(on: true)
        }
    }

    private func syncIfNeeded(forcePowerUpdate: Bool = false) {
        guard state.shouldPoll else { return }

        let brightness = displayManager.getBrightness()

        // Built-in at its minimum: switch the external monitors fully off.
        if brightness <= powerOffThreshold {
            if !externalsPoweredOff || forcePowerUpdate {
                externalsPoweredOff = true
                lastSyncedBrightness = brightness
                ExternalDisplayManager.shared.setPower(on: false)
            }
            return
        }

        // Coming back up from off: power the monitors on, then mirror brightness
        // on the next tick once they have woken.
        if externalsPoweredOff {
            externalsPoweredOff = false
            lastSyncedBrightness = -1
            ExternalDisplayManager.shared.setPower(on: true)
            let generation = state.topologyGeneration
            wakeSyncTask?.cancel()
            wakeSyncTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                guard let self, self.state.topologyGeneration == generation else { return }
                self.wakeSyncTask = nil
                self.syncIfNeeded()
            }
            return
        }

        guard abs(brightness - lastSyncedBrightness) > changeThreshold else { return }
        lastSyncedBrightness = brightness
        ExternalDisplayManager.shared.setBrightness(percentage: brightness)
    }

    @objc private func screenParametersChanged() {
        guard state.isRunning else { return }
        refreshDisplayTopology()
    }

    @objc private func builtInBrightnessChanged() {
        syncIfNeeded()
    }

    private func refreshDisplayTopology() {
        timerCancellable?.cancel()
        timerCancellable = nil
        wakeSyncTask?.cancel()
        wakeSyncTask = nil
        displayManager.configureDisplays()
        let generation = state.topologyChanged(
            hasBuiltInDisplay: displayManager.existBuiltInDisplay
        )
        lastSyncedBrightness = -1
        guard state.hasBuiltInDisplay else { return }

        ExternalDisplayManager.shared.refresh { [weak self] count in
            Task { @MainActor [weak self] in
                self?.completeRefresh(generation: generation, externalDisplayCount: count)
            }
        }
    }

    private func completeRefresh(generation: UInt64, externalDisplayCount: Int) {
        guard state.acceptRefresh(
            generation: generation,
            externalDisplayCount: externalDisplayCount
        ) else { return }
        guard state.shouldPoll else { return }

        syncIfNeeded(forcePowerUpdate: true)
        timerCancellable = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncIfNeeded()
                }
            }
    }
}
