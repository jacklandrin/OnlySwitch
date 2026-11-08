//
//  ScrollDirectionEventTap.swift
//  OnlySwitch
//

@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation

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
