import AppKit
import Combine
import Defines
import DisplayBrightness
import DisplayDDC

/// AppKit/native effects stay on the main actor; blocking I2C uses DisplayDDC's shared queue.
@MainActor
final class DisplayBrightnessService {
    static let shared = DisplayBrightnessService()
    private let shades = DisplayShadeController()
    private let ddc = DDCDisplayController.shared
    private var tokens: [UInt32: DDCDisplayToken] = [:]
    private var continuations: [UUID: AsyncStream<BrightnessSnapshot>.Continuation] = [:]
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var discoveryRevision: UInt64 = 0
    private var syncState = BrightnessNativeSyncState()
    private var outputRevision: UInt64 = 0
    private var isSleeping = false
    private var hasStarted = false
    private var keyboardStatus: BrightnessKeyStatus = .inactive
    private var keyboardTasks: [UInt32: Task<Void, Never>] = [:]
    private var keyboardAccumulator = BrightnessKeyAccumulator()
    private lazy var keyboardController = DisplayBrightnessKeyboardController(
        onKey: { [weak self] key, fine, ids, generation in
            self?.handleBrightnessKey(key, fine: fine, ids: ids, generation: generation)
        },
        onStatus: { [weak self] status in
            guard let self, self.keyboardStatus != status else { return }
            self.keyboardStatus = status
            self.yieldSnapshot(self.coordinator.snapshot)
        })
    private lazy var coordinator = BrightnessCoordinator(write: { [weak self] id, output in
        guard let self else { return false }
        return await self.write(id: id, output: output)
    })

    private lazy var outputWriter = BrightnessOutputWriter(
        hardware: { [weak self] id, level in
            guard let self else { return false }
            return await self.writeHardware(id: id, level: level)
        },
        software: { [weak self] id, factor in self?.shades.apply(factor, to: id) ?? false },
        authorization: { [weak self] id in
            guard let self, !self.isSleeping,
                  NSScreen.screens.contains(where: { $0.displayID == id }),
                  self.coordinator.snapshot.displays.contains(where: { $0.id == id }) else { return nil }
            return .init(topology: self.coordinator.snapshot.generation,
                         recovery: self.outputRevision, intent: self.coordinator.intentRevision(for: id))
        })

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isSleeping = false
        let center = NotificationCenter.default
        for name in [NSApplication.didChangeScreenParametersNotification, .builtInDisplayBrightnessDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let topologyChanged = note.name == NSApplication.didChangeScreenParametersNotification
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if topologyChanged { await self.topologyChanged() }
                    else { await self.pollNative() }
                }
            })
        }
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let settings = DisplayBrightnessSettingsPersistence.load()
                if settings != self.coordinator.settings { await self.updateSettings(settings) }
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sleep() }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }; self.isSleeping = false; await self.topologyChanged()
            }
        })
        coordinator.didChange = { [weak self] snapshot in self?.publish(snapshot) }
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updateSettings(DisplayBrightnessSettingsPersistence.load())
            _ = await self.scan()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                self.updateKeyboardRouting()
                await self.pollNative()
            }
        }
    }

    func scan() async -> BrightnessSnapshot {
        start()
        guard !isSleeping else { return presentedSnapshot(coordinator.snapshot) }
        discoveryRevision &+= 1
        let revision = discoveryRevision
        let previous = coordinator.snapshot.displays
        let screens = NSScreen.screens.filter { $0.displayID != 0 && CGDisplayMirrorsDisplay($0.displayID) == kCGNullDirectDisplay }
        let readings = await ddc.brightnessDisplays()
        guard revision == discoveryRevision, !isSleeping else { return presentedSnapshot(coordinator.snapshot) }
        tokens.removeAll()
        let identities = readings.map(\.identity)
        let screenIdentities = screens.map {
            DDCDisplayIdentity(vendor: CGDisplayVendorNumber($0.displayID), product: CGDisplayModelNumber($0.displayID), serial: CGDisplaySerialNumber($0.displayID))
        }
        var displays: [BrightnessDisplay] = []
        for screen in screens {
            let id = screen.displayID
            let control: DisplayBrightness.BrightnessControl
            let level: Double
            if let native = nativeBrightness(id) {
                control = .native; level = native
                syncState.recordOwnWrite(id: id, level: native)
            } else {
                let identity = DDCDisplayIdentity(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
                if identity.uniqueIndex(in: screenIdentities) != nil,
                   let index = identity.uniqueIndex(in: identities) {
                    control = .ddc
                    tokens[id] = readings[index].token
                    level = BrightnessPolicy.level(hardware: Double(readings[index].percent) / 100, control: .ddc, settings: coordinator.settings)
                } else { control = .software; level = shades.factor(for: id) }
            }
            let preserved = shades.factor(for: id) < 1 ? previous.first(where: { $0.id == id && $0.control == control })?.level : nil
            displays.append(.init(id: id, name: screen.localizedName, control: control, level: preserved ?? level))
        }
        coordinator.replaceInventory(displays)
        return presentedSnapshot(coordinator.snapshot)
    }

    func apply(_ request: BrightnessRequest) async throws {
        guard !isSleeping else { throw BrightnessError.unavailable }
        keyboardTasks.removeValue(forKey: request.screenID)?.cancel()
        keyboardAccumulator.cancel(screenID: request.screenID)
        if coordinator.snapshot.displays.first(where: { $0.id == request.screenID })?.control == .native {
            NotificationCenter.default.post(name: .init("OnlySwitchManualNativeBrightness"), object: NSNumber(value: request.screenID))
        }
        try await coordinator.apply(request)
    }

    func updateSettings(_ settings: BrightnessSettings) async {
        guard settings != coordinator.settings else { return }
        if !settings.controlWithBrightnessKeys { cancelKeyboardAdjustments() }
        outputRevision &+= 1
        _ = syncState.beginCycle()
        if !settings.combinedDimming {
            for display in coordinator.snapshot.displays where display.control == .ddc { shades.remove(display.id) }
        }
        if !settings.allowZeroSoftwareBrightness {
            for display in coordinator.snapshot.displays where shades.factor(for: display.id) < 0.1 {
                _ = shades.apply(0.1, to: display.id)
            }
        }
        await coordinator.updateSettings(settings)
    }

    func resetSoftwareDimming() async {
        cancelKeyboardAdjustments()
        outputRevision &+= 1
        shades.reset()
        await coordinator.resetSoftwareDimming()
    }

    func events() -> AsyncStream<BrightnessSnapshot> {
        start()
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.yield(presentedSnapshot(coordinator.snapshot))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    func stop() {
        cancelKeyboardAdjustments()
        keyboardController.stop()
        outputRevision &+= 1
        pollTask?.cancel(); pollTask = nil
        discoveryRevision &+= 1
        coordinator.cancelTransitions()
        coordinator.replaceInventory([])
        shades.reset(); tokens.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll(); workspaceObservers.removeAll()
        continuations.values.forEach { $0.finish() }; continuations.removeAll()
        hasStarted = false
    }

    private func sleep() {
        cancelKeyboardAdjustments()
        keyboardController.stop()
        outputRevision &+= 1
        isSleeping = true
        discoveryRevision &+= 1
        coordinator.cancelTransitions()
        shades.reset(); tokens.removeAll(); syncState.invalidate()
        coordinator.replaceInventory([])
    }

    private func topologyChanged() async {
        cancelKeyboardAdjustments()
        outputRevision &+= 1
        discoveryRevision &+= 1
        coordinator.cancelTransitions()
        shades.reset(); tokens.removeAll(); syncState.invalidate()
        coordinator.replaceInventory([])
        await ddc.invalidateBrightnessDisplays()
        guard !isSleeping else { return }
        _ = await scan()
    }

    private func nativeBrightness(_ id: UInt32) -> Double? {
        var level: Float = -1
        guard DisplayServicesGetBrightness(id, &level) == 0, level.isFinite, (0...1).contains(level) else { return nil }
        return Double(level)
    }

    private func write(id: UInt32, output: BrightnessOutput) async -> Bool {
        await outputWriter.apply(id: id, output: output)
    }

    private func writeHardware(id: UInt32, level: Double) async -> Bool {
        if let token = tokens[id] {
            return await ddc.setBrightness(Int((level * 100).rounded()), token: token)
        }
        guard coordinator.snapshot.displays.first(where: { $0.id == id })?.control == .native,
              DisplayServicesSetBrightness(id, Float(level)) == 0 else { return false }
        syncState.recordOwnWrite(id: id, level: level)
        return true
    }

    private func pollNative() async {
        guard !isSleeping else { return }
        let native = coordinator.snapshot.displays.filter { $0.control == .native }
        let source = native.first(where: { CGDisplayIsBuiltin($0.id) != 0 }) ?? native.sorted(by: { $0.id < $1.id }).first
        var sourceChange: Double?
        for display in native {
            guard let value = nativeBrightness(display.id) else { continue }
            let changed = syncState.observe(id: display.id, level: value)
            coordinator.observeNative(id: display.id, level: value)
            if display.id == source?.id && changed { sourceChange = value }
        }
        // A duplicate observation must not invalidate the in-flight pass that is reaching later screens.
        guard coordinator.settings.syncNativeBrightness, let value = sourceChange else { return }
        let revision = syncState.beginCycle()
        let generation = coordinator.snapshot.generation
        let targets = coordinator.snapshot.displays.map { ($0, coordinator.intentRevision(for: $0.id)) }
        for (target, intent) in targets where target.control != .native && target.control != .unavailable {
            guard syncState.isCurrent(revision), coordinator.settings.syncNativeBrightness,
                  generation == coordinator.snapshot.generation else { return }
            guard coordinator.intentRevision(for: target.id) == intent else { continue }
            try? await coordinator.apply(.init(screenID: target.id, generation: generation, level: value, revision: 0))
        }
    }

    func requestKeyboardAccess() { keyboardController.requestAccess() }

    private func updateKeyboardRouting() {
        let targets = coordinator.snapshot.displays.map {
            BrightnessKeyTarget(id: $0.id, frame: CGDisplayBounds($0.id),
                                isBuiltIn: CGDisplayIsBuiltin($0.id) != 0,
                                isAvailable: $0.control != .unavailable)
        }
        keyboardController.update(targets: targets, generation: coordinator.snapshot.generation,
                                  enabled: hasStarted && coordinator.settings.controlWithBrightnessKeys,
                                  isSleeping: isSleeping)
    }

    private func handleBrightnessKey(_ key: BrightnessKeyEvent.Key, fine: Bool, ids: [UInt32], generation: UInt64) {
        guard hasStarted, !isSleeping, coordinator.settings.controlWithBrightnessKeys,
              generation == coordinator.snapshot.generation else { return }
        for id in ids {
            guard CGDisplayIsBuiltin(id) == 0,
                  let display = coordinator.snapshot.displays.first(where: { $0.id == id }),
                  display.control != .unavailable else { continue }
            let adjustment = keyboardAccumulator.next(screenID: id, current: display.level, key: key, fine: fine)
            keyboardTasks[id]?.cancel()
            keyboardTasks[id] = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                if display.control == .native {
                    NotificationCenter.default.post(name: .init("OnlySwitchManualNativeBrightness"), object: NSNumber(value: id))
                }
                do {
                    try await self.coordinator.apply(.init(screenID: id, generation: generation,
                                                          level: adjustment.level, revision: 0))
                } catch { /* The coordinator publishes hardware failure; cancellation is ordinary supersession. */ }
                self.keyboardAccumulator.finish(screenID: id, revision: adjustment.revision)
            }
        }
    }

    private func cancelKeyboardAdjustments() {
        keyboardTasks.values.forEach { $0.cancel() }
        keyboardTasks.removeAll()
        keyboardAccumulator.reset()
    }

    private func presentedSnapshot(_ snapshot: BrightnessSnapshot) -> BrightnessSnapshot {
        var presented = snapshot
        presented.brightnessKeyStatus = keyboardStatus
        return presented
    }

    private func yieldSnapshot(_ snapshot: BrightnessSnapshot) {
        let presented = presentedSnapshot(snapshot)
        continuations.values.forEach { $0.yield(presented) }
    }

    private func publish(_ snapshot: BrightnessSnapshot) {
        updateKeyboardRouting()
        yieldSnapshot(snapshot)
    }
}
