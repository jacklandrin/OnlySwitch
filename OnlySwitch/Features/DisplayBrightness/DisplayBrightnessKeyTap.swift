import AppKit
import ApplicationServices
import DisplayBrightness

/// The callback resolves a frozen, lock-protected routing snapshot without waiting for the main actor.
/// Only this dedicated thread touches its run-loop source; start/stop never block another executor.
final class DisplayBrightnessKeyTap: @unchecked Sendable {
    private final class Context {
        weak var owner: DisplayBrightnessKeyTap?
        let session: UInt64
        init(owner: DisplayBrightnessKeyTap, session: UInt64) { self.owner = owner; self.session = session }
    }
    private let lock = NSLock()
    private let onKey: @MainActor (BrightnessKeyEvent.Key, Bool, [UInt32], UInt64) -> Void
    private let onStatus: @MainActor (BrightnessKeyStatus) -> Void
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var session: UInt64 = 0
    private var running = false
    private var starting = false
    private var enabled = false
    private var generation: UInt64 = 0
    private var targets: [BrightnessKeyTarget] = []
    private var routing = BrightnessKeyRoutingState()
    private var reportedRevocation = false

    init(onKey: @escaping @MainActor (BrightnessKeyEvent.Key, Bool, [UInt32], UInt64) -> Void,
         onStatus: @escaping @MainActor (BrightnessKeyStatus) -> Void) {
        self.onKey = onKey; self.onStatus = onStatus
    }
    deinit { stop() }
    var isRunning: Bool { withLock { running } }
    var isStarting: Bool { withLock { starting } }
    var hasCapturedGesture: Bool { withLock { routing.hasCapturedGesture } }

    func update(targets: [BrightnessKeyTarget], generation: UInt64, enabled: Bool) {
        withLock {
            if !enabled { routing.reset() }
            self.targets = targets; self.generation = generation; self.enabled = enabled
        }
    }

    func start() {
        let launch: Thread? = withLock {
            guard !running, !starting, enabled else { return nil }
            session &+= 1
            let token = session
            starting = true
            reportedRevocation = false
            let thread = Thread { [weak self] in self?.run(session: token) }
            thread.name = "OnlySwitch.DisplayBrightnessKeyTap"
            self.thread = thread
            return thread
        }
        launch?.start()
    }

    func stop() {
        let target: CFRunLoop? = withLock {
            session &+= 1
            enabled = false; running = false; starting = false
            routing.reset(); thread = nil; eventTap = nil
            defer { runLoop = nil }
            return runLoop
        }
        if let target {
            CFRunLoopPerformBlock(target, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(target) }
            CFRunLoopWakeUp(target)
        }
    }

    private func run(session token: UInt64) {
        autoreleasepool {
            guard let loop = CFRunLoopGetCurrent() else { notify(.unavailable, session: token); return }
            let context = Context(owner: self, session: token)
            let mask = CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue)
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, pointer in
                    guard let pointer else { return Unmanaged.passUnretained(event) }
                    let context = Unmanaged<Context>.fromOpaque(pointer).takeUnretainedValue()
                    guard let owner = context.owner else { return Unmanaged.passUnretained(event) }
                    return owner.handle(type: type, event: event, session: context.session)
                }, userInfo: Unmanaged.passUnretained(context).toOpaque()),
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                withLock { if session == token { starting = false; thread = nil } }
                notify(AXIsProcessTrusted() ? .unavailable : .needsAccessibility, session: token)
                return
            }
            defer {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(loop, source, .commonModes)
                CFRunLoopSourceInvalidate(source)
                CFMachPortInvalidate(tap)
                withLock {
                    if session == token {
                        running = false; starting = false; runLoop = nil; eventTap = nil; thread = nil
                    }
                }
            }
            let accepted = withLock {
                guard session == token, enabled else { return false }
                runLoop = loop; eventTap = tap
                return true
            }
            guard accepted else { return }
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            let didStart = CGEvent.tapIsEnabled(tap: tap)
            let shouldRun = withLock {
                guard session == token, enabled else { return false }
                running = didStart; starting = false
                return didStart
            }
            guard shouldRun else { notify(.unavailable, session: token); return }
            notify(.ready, session: token)
            withExtendedLifetime(context) { CFRunLoopRun() }
        }
    }

    private func handle(type: CGEventType, event: CGEvent, session token: UInt64) -> Unmanaged<CGEvent>? {
        let trusted = AXIsProcessTrusted()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let tap = withLock { session == token && enabled && trusted ? eventTap : nil }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue),
              let nsEvent = NSEvent(cgEvent: event),
              let key = BrightnessKeyEvent(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }
        // A systemDefined event's stored position can be stale; query the live Quartz pointer.
        let pointer = CGEvent(source: nil)?.location ?? CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)
        let route: BrightnessKeyRoute? = withLock {
            guard session == token, running else { return nil }
            return routing.route(key, targets: targets, pointer: pointer, generation: generation,
                                 enabled: enabled, trusted: trusted)
        }
        if !trusted {
            let first = withLock { () -> Bool in
                guard session == token, !reportedRevocation else { return false }
                reportedRevocation = true; return true
            }
            if first { notify(.needsAccessibility, session: token) }
        }
        guard let route else { return Unmanaged.passUnretained(event) }
        if key.isKeyDown, !route.ids.isEmpty {
            let fine = event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)
            let onKey = onKey
            DispatchQueue.main.async { [weak self] in
                guard let self, AXIsProcessTrusted(), self.authorizes(route, session: token) else { return }
                MainActor.assumeIsolated { onKey(key.key, fine, route.ids, route.generation) }
            }
        }
        return nil
    }

    private func authorizes(_ route: BrightnessKeyRoute, session token: UInt64) -> Bool {
        withLock {
            session == token && running
                && BrightnessKeyPolicy.authorizes(route, targets: targets, generation: generation, enabled: enabled)
        }
    }
    private func notify(_ status: BrightnessKeyStatus, session token: UInt64) {
        let onStatus = onStatus
        DispatchQueue.main.async { [weak self] in
            guard let self, self.withLock({ self.session == token }) else { return }
            MainActor.assumeIsolated { onStatus(status) }
        }
    }
    private func withLock<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}
