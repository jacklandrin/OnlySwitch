//
//  BrightnessSyncManager.swift
//  OnlySwitch
//
//  Keeps external monitors in lock-step with the built-in display's brightness.
//
//  macOS only routes the F1/F2 brightness keys – and the ambient-light sensor,
//  Control Center slider, the Dim Screen switch, etc. – to the built-in panel.
//  We poll the built-in brightness and, whenever it moves, push the same 0...1
//  level to every external display over DDC/CI. So dimming the built-in screen
//  dims all connected monitors to the same level automatically. At the built-in
//  panel's minimum the external monitors are switched fully off (DPMS) so they go
//  dark together, and powered back on as soon as the brightness rises again.
//

import Foundation
import AppKit
import Combine

@MainActor
final class BrightnessSyncManager {
    static let shared = BrightnessSyncManager()

    private let displayManager = DisplayManager()
    private var timerCancellable: AnyCancellable?
    private var lastSyncedBrightness: Float = -1
    private var externalsPoweredOff = false
    private var isRunning = false

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
        guard !isRunning else { return }
        isRunning = true
        lastSyncedBrightness = -1
        ExternalDisplayManager.shared.refresh()
        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.syncIfNeeded()
            }
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
        // Don't leave external monitors stuck in DPMS off when syncing is disabled.
        if externalsPoweredOff {
            externalsPoweredOff = false
            ExternalDisplayManager.shared.setPower(on: true)
        }
    }

    private func syncIfNeeded() {
        displayManager.configureDisplays()
        guard displayManager.existBuiltInDisplay else { return }

        let brightness = displayManager.getBrightness()

        // Built-in at its minimum: switch the external monitors fully off.
        if brightness <= powerOffThreshold {
            if !externalsPoweredOff {
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
            return
        }

        guard abs(brightness - lastSyncedBrightness) > changeThreshold else { return }
        lastSyncedBrightness = brightness
        ExternalDisplayManager.shared.setBrightness(percentage: brightness)
    }

    @objc private func screenParametersChanged() {
        guard isRunning else { return }
        // A monitor was (dis)connected – rebuild the DDC cache and re-mirror.
        lastSyncedBrightness = -1
        externalsPoweredOff = false
        ExternalDisplayManager.shared.refresh()
    }
}
