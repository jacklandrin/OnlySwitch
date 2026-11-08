import AppKit
import DisplayDDC

/// Consumes volume media keys while ``interceptsVolumeKeys`` is set, so they can drive a display's
/// DDC volume. Runs on its own thread: the callback must answer synchronously and never wait on
/// the main actor. Requires Accessibility.
final class DisplayVolumeKeyTap: @unchecked Sendable {
    private let lock = NSLock()
    private let onKey: @MainActor (VolumeKeyEvent.Key, Bool) -> Void
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var running = false
    private var intercepts = false

    init(onKey: @escaping @MainActor (VolumeKeyEvent.Key, Bool) -> Void) {
        self.onKey = onKey
    }

    deinit { stop() }

    var interceptsVolumeKeys: Bool {
        get { withLock { intercepts } }
        set { withLock { intercepts = newValue } }
    }

    var isRunning: Bool { withLock { running } }

    func start() -> Bool {
        if isRunning { return true }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in self?.run(signaling: ready) }
        thread.name = "OnlySwitch.DisplayVolumeKeyTap"
        withLock { self.thread = thread }
        thread.start()
        ready.wait()
        return isRunning
    }

    func stop() {
        guard let target = withLock({ runLoop }) else {
            withLock { running = false; thread = nil }
            return
        }
        let stopped = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(target, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.tearDown(on: target)
            CFRunLoopStop(target)
            stopped.signal()
        }
        CFRunLoopWakeUp(target)
        stopped.wait()
    }

    private func run(signaling ready: DispatchSemaphore) {
        autoreleasepool {
            guard let current = CFRunLoopGetCurrent() else { ready.signal(); return }
            let mask = CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<DisplayVolumeKeyTap>.fromOpaque(userInfo)
                        .takeUnretainedValue().handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                ready.signal()
                return
            }
            CFRunLoopAddSource(current, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            let didStart = CGEvent.tapIsEnabled(tap: tap)
            withLock {
                runLoop = current
                eventTap = tap
                runLoopSource = source
                running = didStart
            }
            guard didStart else {
                tearDown(on: current)
                ready.signal()
                return
            }
            ready.signal()
            CFRunLoopRun()
            tearDown(on: current)
            withLock { if thread === Thread.current { thread = nil } }
        }
    }

    private func tearDown(on target: CFRunLoop) {
        let (tap, source) = withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            defer { eventTap = nil; runLoopSource = nil; runLoop = nil; running = false }
            return (eventTap, runLoopSource)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source {
            CFRunLoopRemoveSource(target, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap { CFMachPortInvalidate(tap) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = withLock({ eventTap }) { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard interceptsVolumeKeys,
              type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue),
              let nsEvent = NSEvent(cgEvent: event),
              let key = VolumeKeyEvent(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1)
        else { return Unmanaged.passUnretained(event) }
        if key.isKeyDown {
            let fine = event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)
            let onKey = onKey
            DispatchQueue.main.async { MainActor.assumeIsolated { onKey(key.key, fine) } }
        }
        return nil
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
