@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Darwin
import Defines
import Extensions
import Foundation
import Switches

struct ScrollWheelEventTraits: Equatable, Sendable {
    let isContinuous: Bool
    let scrollPhase: Int64
    let momentumPhase: Int64
    let tabletDeviceID: Int64
    let sourceUserData: Int64
    let vertical: VerticalScrollDeltas
    let horizontal: VerticalScrollDeltas

    var shouldInvert: Bool {
        isContinuous == false
            && scrollPhase == 0
            && momentumPhase == 0
            && tabletDeviceID == 0
            && sourceUserData != ScrollDirectionEventTap.syntheticEventTag
            && vertical.hasMovement
            && horizontal.hasMovement == false
    }
}

struct VerticalScrollDeltas: Equatable, Sendable {
    let line: Int64
    let point: Int64
    /// `scrollWheelEventFixedPtDeltaAxis*` stores a signed 16.16 fixed-point
    /// integer. Reading and writing it as an integer preserves the raw value
    /// that AppKit receives from a physical wheel.
    let fixedPoint: Int64

    var hasMovement: Bool {
        line != 0 || point != 0 || fixedPoint != 0
    }

    var inverted: Self {
        Self(
            line: Self.safelyNegating(line),
            point: Self.safelyNegating(point),
            fixedPoint: Self.safelyNegating(fixedPoint)
        )
    }

    private static func safelyNegating(_ value: Int64) -> Int64 {
        value == .min ? .max : -value
    }
}

struct ReverseScrollRuntimeState: Equatable, Sendable {
    private(set) var isRequested: Bool
    private(set) var isRunning = false

    init(isRequested: Bool) {
        self.isRequested = isRequested
    }

    var currentStatus: Bool {
        isRequested && isRunning
    }

    mutating func didStart() {
        isRunning = true
    }

    mutating func didStop() {
        isRunning = false
    }

    mutating func setRequested(_ isRequested: Bool) {
        self.isRequested = isRequested
        if !isRequested {
            isRunning = false
        }
    }
}

struct GlobalScrollDirectionPreference: Sendable {
    let setNatural: @MainActor @Sendable (Bool) -> Bool

    static let live = Self(
        setNatural: { isNatural in
            let key = "com.apple.swipescrolldirection" as CFString
            CFPreferencesSetValue(
                key,
                NSNumber(value: isNatural),
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            let didSynchronize = CFPreferencesSynchronize(
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            applyScrollDirectionImmediately(isNatural)
            let storedValue = CFPreferencesCopyValue(
                key,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            return didSynchronize && (storedValue as? NSNumber)?.boolValue == isNatural
        }
    )

    private static func applyScrollDirectionImmediately(_ isNatural: Bool) {
        typealias ApplyScrollDirection = @convention(c) (Bool) -> Void
        let frameworkPath = "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"

        if let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) {
            defer { dlclose(handle) }
            if let symbol = dlsym(handle, "setSwipeScrollDirection") {
                let apply = unsafeBitCast(symbol, to: ApplyScrollDirection.self)
                apply(isNatural)
                return
            }
        }

        DistributedNotificationCenter.default().post(
            name: Notification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil
        )
    }
}

@MainActor
@discardableResult
func restoreLegacyScrollDirectionIfNeeded(
    defaults: UserDefaults,
    preference: GlobalScrollDirectionPreference
) -> Bool {
    let key = UserDefaults.Key.reverseScrollDirectionOriginalNaturalScrolling
    guard let originalValue = defaults.object(forKey: key) as? Bool else {
        return true
    }
    guard preference.setNatural(originalValue) else {
        return false
    }
    defaults.removeObject(forKey: key)
    return true
}

@MainActor
final class ReverseScrollDirectionController {
    static let shared = ReverseScrollDirectionController()

    private let defaults: UserDefaults
    private var state: ReverseScrollRuntimeState
    private var eventTap: ScrollDirectionEventTap?

    init(
        defaults: UserDefaults = .standard,
        globalScrollDirection: GlobalScrollDirectionPreference = .live
    ) {
        self.defaults = defaults
        let isRequested = defaults.object(
            forKey: UserDefaults.Key.reverseScrollDirectionEnabled
        ) as? Bool ?? false
        state = ReverseScrollRuntimeState(isRequested: isRequested)

        _ = restoreLegacyScrollDirectionIfNeeded(
            defaults: defaults,
            preference: globalScrollDirection
        )

        if defaults.object(forKey: UserDefaults.Key.reverseScrollDirectionEnabled) == nil {
            defaults.set(false, forKey: UserDefaults.Key.reverseScrollDirectionEnabled)
        }
        if state.isRequested {
            try? start(promptForAccessibility: true)
        }
    }

    isolated deinit {
        eventTap?.stop()
    }

    func currentStatus() -> Bool {
        if state.isRequested, eventTap?.isRunning != true {
            state.didStop()
            try? start(promptForAccessibility: true)
        }
        return state.currentStatus && eventTap?.isRunning == true
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            do {
                try start(promptForAccessibility: true)
                state.setRequested(true)
                state.didStart()
                defaults.set(true, forKey: UserDefaults.Key.reverseScrollDirectionEnabled)
            } catch {
                eventTap?.stop()
                eventTap = nil
                state.didStop()
                throw SwitchError.OperationFailed
            }
        } else {
            state.setRequested(false)
            defaults.set(false, forKey: UserDefaults.Key.reverseScrollDirectionEnabled)
            eventTap?.stop()
            eventTap = nil
        }
    }

    func suspendForTermination() {
        eventTap?.stop()
        eventTap = nil
        state.didStop()
    }

    private func start(promptForAccessibility: Bool) throws {
        guard accessibilityIsGranted(prompt: promptForAccessibility) else {
            throw SwitchError.OperationFailed
        }

        if eventTap?.isRunning == true {
            state.didStart()
            return
        }

        eventTap?.stop()
        let newEventTap = ScrollDirectionEventTap()
        guard newEventTap.start() else {
            newEventTap.stop()
            throw SwitchError.OperationFailed
        }
        eventTap = newEventTap
        state.didStart()
    }

    private func accessibilityIsGranted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

final class ReverseScrollDirectionSwitch: SwitchProvider, @unchecked Sendable {
    weak var delegate: SwitchDelegate?
    let type: SwitchType = .reverseScrollDirection

    private let readStatus: @MainActor @Sendable () async throws -> Bool
    private let writeStatus: @MainActor @Sendable (Bool) async throws -> Void

    init(
        readStatus: @escaping @MainActor @Sendable () async throws -> Bool = {
            ReverseScrollDirectionController.shared.currentStatus()
        },
        writeStatus: @escaping @MainActor @Sendable (Bool) async throws -> Void = { isOn in
            try ReverseScrollDirectionController.shared.setEnabled(isOn)
        }
    ) {
        self.readStatus = readStatus
        self.writeStatus = writeStatus
    }

    @MainActor
    func currentStatus() async -> Bool {
        (try? await readStatus()) ?? false
    }

    @MainActor
    func currentInfo() async -> String {
        ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            try await writeStatus(isOn)
        } catch {
            throw SwitchError.OperationFailed
        }
    }

    func isVisible() -> Bool {
        true
    }
}
