import AppKit
import ApplicationServices
import DisplayBrightness

@MainActor
final class DisplayBrightnessKeyboardController {
    private let onStatus: @MainActor (BrightnessKeyStatus) -> Void
    private let onKey: @MainActor (BrightnessKeyEvent.Key, Bool, [UInt32], UInt64) -> Void
    private lazy var tap = DisplayBrightnessKeyTap(onKey: onKey, onStatus: { [weak self] value in
        self?.report(value)
    })
    private var targets: [BrightnessKeyTarget] = []
    private var generation: UInt64 = 0
    private var wantsControl = false
    private var requestedControl = false
    private var status: BrightnessKeyStatus = .inactive
    private var permissionTask: Task<Void, Never>?
    private var lastTrust: Bool?

    init(onKey: @escaping @MainActor (BrightnessKeyEvent.Key, Bool, [UInt32], UInt64) -> Void,
         onStatus: @escaping @MainActor (BrightnessKeyStatus) -> Void) {
        self.onStatus = onStatus
        self.onKey = onKey
    }

    func update(targets: [BrightnessKeyTarget], generation: UInt64, enabled: Bool, isSleeping: Bool = false) {
        self.targets = targets; self.generation = generation
        requestedControl = enabled && !isSleeping
        // A transient empty/new inventory invalidates dispatch while preserving an already consumed key pair.
        tap.update(targets: targets, generation: generation, enabled: requestedControl)
        refreshAccess()
        if wantsControl, permissionTask == nil {
            permissionTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard let self else { return }
                    let trusted = AXIsProcessTrusted()
                    if trusted != self.lastTrust || !self.targets.contains(where: { !$0.isBuiltIn && $0.isAvailable }) {
                        self.refreshAccess()
                    }
                }
            }
        } else if !wantsControl {
            permissionTask?.cancel(); permissionTask = nil
        }
    }

    /// Only an explicit user action requests permission or opens System Settings.
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshAccess()
    }

    func stop() {
        requestedControl = false
        wantsControl = false
        permissionTask?.cancel(); permissionTask = nil
        tap.stop()
        report(.inactive)
    }

    private func refreshAccess() {
        wantsControl = requestedControl && (targets.contains { !$0.isBuiltIn && $0.isAvailable } || tap.hasCapturedGesture)
        let trusted = AXIsProcessTrusted()
        lastTrust = trusted
        guard wantsControl else { tap.stop(); report(.inactive); return }
        guard trusted else { tap.stop(); report(.needsAccessibility); return }
        tap.update(targets: targets, generation: generation, enabled: true)
        if !tap.isRunning, !tap.isStarting { tap.start() }
        if tap.isRunning { report(.ready) }
    }

    private func report(_ value: BrightnessKeyStatus) {
        guard value != status else { return }
        status = value; onStatus(value)
    }
}
