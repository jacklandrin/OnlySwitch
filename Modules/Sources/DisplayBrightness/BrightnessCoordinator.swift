import Foundation

/// Serializes intent, not the executor: every suspension checks the current operation and topology.
@MainActor
public final class BrightnessCoordinator {
    public private(set) var snapshot = BrightnessSnapshot()
    public private(set) var settings: BrightnessSettings
    public var didChange: (@MainActor (BrightnessSnapshot) -> Void)?
    private let write: @MainActor (UInt32, BrightnessOutput) async -> Bool
    private let sleep: @Sendable (Duration) async throws -> Void
    private var revisions: [UInt32: UInt64] = [:]
    private var operation: UInt64 = 0
    private var settingsRevision: UInt64 = 0
    private var latestRequests: [UInt32: UInt64] = [:]
    private var intentVersions: [UInt32: UInt64] = [:]
    public func intentRevision(for id: UInt32) -> UInt64 { intentVersions[id] ?? 0 }

    public init(settings: BrightnessSettings = .init(),
                write: @escaping @MainActor (UInt32, BrightnessOutput) async -> Bool,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.settings = settings; self.write = write; self.sleep = sleep
    }

    public func replaceInventory(_ displays: [BrightnessDisplay]) {
        snapshot.generation &+= 1
        snapshot.displays = displays
        revisions.removeAll()
        latestRequests.removeAll()
        intentVersions.removeAll()
        didChange?(snapshot)
    }

    public func apply(_ request: BrightnessRequest, animated: Bool = true) async throws {
        guard request.level.isFinite else { throw BrightnessError.invalidLevel }
        guard request.generation == snapshot.generation else { throw BrightnessError.staleRequest }
        guard let index = snapshot.displays.firstIndex(where: { $0.id == request.screenID }),
              snapshot.displays[index].control != .unavailable else { throw BrightnessError.unavailable }
        if request.revision != 0 {
            guard request.revision > (latestRequests[request.screenID] ?? 0) else { throw BrightnessError.staleRequest }
            latestRequests[request.screenID] = request.revision
            snapshot.displays[index].supersededUIRevision = 0
        } else {
            snapshot.displays[index].supersededUIRevision = latestRequests[request.screenID] ?? 0
        }
        operation &+= 1
        let revision = operation
        intentVersions[request.screenID] = revision
        revisions[request.screenID] = revision
        defer { if revisions[request.screenID] == revision { revisions.removeValue(forKey: request.screenID) } }
        let start = snapshot.displays[index].appliedLevel
        let target = max(0, min(1, request.level))
        let control = snapshot.displays[index].control
        snapshot.displays[index].level = target
        snapshot.displays[index].error = false
        didChange?(snapshot)
        let steps = settings.smoothTransitions && animated ? (control == .ddc ? 3 : 8) : 1
        for step in 1...steps {
            try Task.checkCancellation()
            guard revisions[request.screenID] == revision, snapshot.generation == request.generation else {
                throw BrightnessError.staleRequest
            }
            let level = start + (target - start) * Double(step) / Double(steps)
            let output = BrightnessPolicy.output(level: level, control: control, settings: settings)
            let success = await write(request.screenID, output)
            guard revisions[request.screenID] == revision, snapshot.generation == request.generation,
                  let current = snapshot.displays.firstIndex(where: { $0.id == request.screenID }) else {
                throw BrightnessError.staleRequest
            }
            guard success else {
                snapshot.displays[current].error = true
                didChange?(snapshot)
                throw BrightnessError.writeFailed
            }
            snapshot.displays[current].appliedLevel = level
            didChange?(snapshot)
            if step != steps { try await sleep(.milliseconds(control == .ddc ? 100 : 30)) }
        }
    }

    public func updateSettings(_ settings: BrightnessSettings) async {
        self.settings = settings
        settingsRevision &+= 1
        let revision = settingsRevision
        // Invalidate old transitions before the first suspension.
        revisions.removeAll()
        let requests = snapshot.displays.map {
            (BrightnessRequest(screenID: $0.id, generation: snapshot.generation, level: $0.level, revision: 0), intentRevision(for: $0.id))
        }
        for (request, intent) in requests {
            guard revision == settingsRevision else { return }
            guard intentRevision(for: request.screenID) == intent else { continue }
            try? await apply(request)
        }
    }

    public func cancelTransitions() { revisions.removeAll() }

    public func resetSoftwareDimming() async {
        revisions.removeAll()
        let generation = snapshot.generation
        let displays = snapshot.displays.map { ($0, intentRevision(for: $0.id)) }
        for (display, intent) in displays where display.control == .software || display.control == .ddc {
            guard generation == snapshot.generation, intentRevision(for: display.id) == intent else { continue }
            let level = display.control == .software ? 1 : (settings.combinedDimming ? max(0.2, display.appliedLevel) : display.appliedLevel)
            try? await apply(.init(screenID: display.id, generation: generation, level: level, revision: 0), animated: false)
        }
    }

    /// Refresh native observations without treating them as slider intent.
    public func observeNative(id: UInt32, level: Double) {
        guard revisions[id] == nil, let index = snapshot.displays.firstIndex(where: { $0.id == id }) else { return }
        snapshot.displays[index].level = level
        snapshot.displays[index].appliedLevel = level
        didChange?(snapshot)
    }
}
