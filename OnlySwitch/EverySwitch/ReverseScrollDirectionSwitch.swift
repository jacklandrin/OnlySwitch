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

/// Owns the event tap and every one of its Core Foundation resources on one
/// dedicated run-loop thread. `NSLock` protects only the small lifecycle
/// snapshot that is read from the main actor.
final class ScrollDirectionEventTap: @unchecked Sendable {
    static let syntheticEventTag: Int64 = 0x4F53_5357_4956_4E54

    private let lock = NSLock()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var running = false

    var isRunning: Bool {
        withLock { running }
    }

    func start() -> Bool {
        if isRunning {
            return true
        }

        stop()

        let ready = DispatchSemaphore(value: 0)
        let eventTapThread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }
            self.runEventTap(signaling: ready)
        }
        eventTapThread.name = "com.jacklandrin.OnlySwitch.scroll-direction-event-tap"
        eventTapThread.qualityOfService = .userInteractive
        withLock {
            thread = eventTapThread
        }
        eventTapThread.start()
        ready.wait()
        return isRunning
    }

    func stop() {
        let targetRunLoop = withLock { runLoop }
        guard let targetRunLoop else {
            withLock {
                running = false
                thread = nil
            }
            return
        }

        let stopped = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(targetRunLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.tearDown(on: targetRunLoop)
            CFRunLoopStop(targetRunLoop)
            stopped.signal()
        }
        CFRunLoopWakeUp(targetRunLoop)
        stopped.wait()
    }

    deinit {
        stop()
    }

    private func runEventTap(signaling ready: DispatchSemaphore) {
        autoreleasepool {
            guard let currentRunLoop = CFRunLoopGetCurrent() else {
                ready.signal()
                return
            }
            let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else {
                        return Unmanaged.passUnretained(event)
                    }
                    let owner = Unmanaged<ScrollDirectionEventTap>
                        .fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return owner.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                ready.signal()
                return
            }

            CFRunLoopAddSource(currentRunLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            let didStart = CGEvent.tapIsEnabled(tap: tap)
            withLock {
                runLoop = currentRunLoop
                eventTap = tap
                runLoopSource = source
                running = didStart
            }

            guard didStart else {
                tearDown(on: currentRunLoop)
                ready.signal()
                return
            }

            ready.signal()
            CFRunLoopRun()
            tearDown(on: currentRunLoop)
            withLock {
                if thread === Thread.current {
                    thread = nil
                }
            }
        }
    }

    private func tearDown(on targetRunLoop: CFRunLoop) {
        let resources = withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let resources = (eventTap, runLoopSource)
            eventTap = nil
            runLoopSource = nil
            runLoop = nil
            running = false
            return resources
        }

        if let tap = resources.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = resources.1 {
            CFRunLoopRemoveSource(targetRunLoop, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap = resources.0 {
            CFMachPortInvalidate(tap)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            guard let tap = withLock({ eventTap }) else {
                return Unmanaged.passUnretained(event)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) == false {
                withLock { running = false }
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        let traits = Self.traits(for: event)
        guard traits.shouldInvert else {
            return Unmanaged.passUnretained(event)
        }

        guard let replacement = Self.makeReplacementEvent(
            from: event,
            invertedVertical: traits.vertical.inverted
        ) else {
            return Unmanaged.passUnretained(event)
        }

        replacement.post(tap: .cgSessionEventTap)
        return nil
    }

    private static func traits(for event: CGEvent) -> ScrollWheelEventTraits {
        ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            tabletDeviceID: event.getIntegerValueField(.tabletEventDeviceID),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData),
            vertical: VerticalScrollDeltas(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                fixedPoint: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
            ),
            horizontal: VerticalScrollDeltas(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                fixedPoint: event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2)
            )
        )
    }

    private static func makeReplacementEvent(
        from original: CGEvent,
        invertedVertical: VerticalScrollDeltas
    ) -> CGEvent? {
        // Build a fresh event rather than modifying the HID event in place.
        // The public scroll-wheel initializer does not consistently preserve
        // line, point, and fixed-point deltas together, so create the base
        // event and set the same fields delivered by a physical wheel.
        guard let replacement = CGEvent(source: nil) else {
            return nil
        }

        replacement.setIntegerValueField(
            CGEventField(rawValue: 55)!, // `kCGEventType` in the raw event layout.
            value: Int64(CGEventType.scrollWheel.rawValue)
        )
        replacement.flags = original.flags
        replacement.setIntegerValueField(
            .scrollWheelEventDeltaAxis1,
            value: invertedVertical.line
        )
        replacement.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: invertedVertical.point
        )
        replacement.setIntegerValueField(
            .scrollWheelEventFixedPtDeltaAxis1,
            value: invertedVertical.fixedPoint
        )
        replacement.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        replacement.setIntegerValueField(
            .scrollWheelEventScrollCount,
            value: original.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        replacement.setIntegerValueField(
            .eventSourceUserData,
            value: syntheticEventTag
        )
        return replacement
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
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
