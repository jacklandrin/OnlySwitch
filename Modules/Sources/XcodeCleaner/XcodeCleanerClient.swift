#if os(macOS)
import Foundation
import Dependencies

public struct XcodeCleanerClient: Sendable {
    public var scan: @Sendable () async throws -> CleanerSnapshot
    public var clean: @Sendable (CleanerCleanupRequest) async throws -> CleanerCleanupResult
    public var activateSnapshot: @Sendable (UUID) async -> Void
    public init(scan: @escaping @Sendable () async throws -> CleanerSnapshot, clean: @escaping @Sendable (CleanerCleanupRequest) async throws -> CleanerCleanupResult, activateSnapshot: @escaping @Sendable (UUID) async -> Void = { _ in }) {
        self.scan = scan; self.clean = clean; self.activateSnapshot = activateSnapshot
    }
}
extension XcodeCleanerClient: DependencyKey {
    public static let liveValue: Self = {
        let coordinator = CleanerCoordinator(home: FileManager.default.homeDirectoryForCurrentUser)
        return Self(scan: { try await coordinator.scan() }, clean: { try await coordinator.clean($0) }, activateSnapshot: { await coordinator.activateSnapshot($0) })
    }()
    public static let testValue = Self(scan: { CleanerSnapshot() }, clean: { _ in CleanerCleanupResult() })
}
public extension DependencyValues {
    var xcodeCleanerClient: XcodeCleanerClient {
        get { self[XcodeCleanerClient.self] }
        set { self[XcodeCleanerClient.self] = newValue }
    }
}

actor CleanerCoordinator {
    private let filesystem: XcodeCleanerClient
    private let simulator: XcodeCleanerClient
    private struct Context: Sendable {
        var sequence: Int
        var revision: Int
        var files: CleanerSnapshot
        var simulators: CleanerSnapshot
    }
    private var contexts: CleanerSnapshotContexts<Context>
    private var sequence = 0
    private var activeSequence = -1
    private var activeID: UUID?
    private var revision = 0
    private var isCleaning = false
    init(filesystem: XcodeCleanerClient, simulator: XcodeCleanerClient, retainedCandidateLimit: Int = 4) {
        self.filesystem = filesystem; self.simulator = simulator
        contexts = .init(candidateLimit: retainedCandidateLimit)
    }
    init(home: URL) {
        let files = XcodeCleanerFileSystem(home: home), sims = XcodeCleanerSimulator(home: home)
        filesystem = .init(scan: { try await files.scan() }, clean: { try await files.clean($0) }, activateSnapshot: { await files.activateSnapshot($0) })
        simulator = .init(scan: { try await sims.scan() }, clean: { try await sims.clean($0) }, activateSnapshot: { await sims.activateSnapshot($0) })
        contexts = .init()
    }
    func scan() async throws -> CleanerSnapshot {
        guard !isCleaning else { throw CancellationError() }
        sequence += 1
        let ticket = sequence, startRevision = revision
        let files = try await filesystem.scan()
        try Task.checkCancellation()
        guard startRevision == revision else { throw CancellationError() }
        let simulators = try await simulator.scan()
        try Task.checkCancellation()
        guard startRevision == revision else { throw CancellationError() }
        let combined = CleanerSnapshot(items: files.items + simulators.items, failures: files.failures + simulators.failures)
        contexts.insert(.init(sequence: ticket, revision: startRevision, files: files, simulators: simulators), id: combined.id, sequence: ticket)
        return combined
    }
    func activateSnapshot(_ id: UUID) async {
        guard let context = contexts[id], context.sequence >= activeSequence,
              context.revision == revision || activeID == id else { return }
        activeSequence = context.sequence; activeID = id
        _ = contexts.activate(id)
        await filesystem.activateSnapshot(context.files.id)
        guard activeID == id else { return }
        await simulator.activateSnapshot(context.simulators.id)
    }
    func clean(_ request: CleanerCleanupRequest) async throws -> CleanerCleanupResult {
        let ids = request.itemIDs.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !isCleaning, let context = contexts[request.snapshotID], !ids.isEmpty,
              context.sequence >= activeSequence || activeID == request.snapshotID,
              context.revision == revision || activeID == request.snapshotID else {
            return .init(failures: ids.map { .init(key: "Xcode Cleaner Stale Scan", itemID: $0) })
        }
        try Task.checkCancellation()
        isCleaning = true; revision += 1; contexts.pin(request.snapshotID)
        // Pin the still-visible authorization before crossing adapter awaits.
        activeID = request.snapshotID; activeSequence = max(activeSequence, context.sequence)
        _ = contexts.activate(request.snapshotID)
        defer { isCleaning = false; contexts.unpin(request.snapshotID) }
        await filesystem.activateSnapshot(context.files.id)
        await simulator.activateSnapshot(context.simulators.id)
        let files = context.files.items, simulators = context.simulators.items
        let fileIDs = ids.filter { id in files.contains { $0.id == id && $0.canClean } }
        let simulatorIDs = ids.filter { id in simulators.contains { $0.id == id && $0.canClean } && !fileIDs.contains(id) }
        var result = CleanerCleanupResult(failures: ids.filter { !fileIDs.contains($0) && !simulatorIDs.contains($0) }.map { .init(key: "Xcode Cleaner Stale Scan", itemID: $0) })
        for (client, snapshot, subset) in [(filesystem, context.files, fileIDs), (simulator, context.simulators, simulatorIDs)] where !subset.isEmpty {
            do {
                let outcome = try await client.clean(.init(snapshotID: snapshot.id, itemIDs: subset))
                let successes = Set(outcome.removedItemIDs).intersection(subset)
                result.removedItemIDs += subset.filter { successes.contains($0) }
                result.failures += outcome.failures.flatMap { failure -> [CleanerFailure] in
                    if let id = failure.itemID { return subset.contains(id) ? [failure] : [] }
                    return subset.filter { !successes.contains($0) }.map { failure.scoped(to: $0, partial: true) }
                }
                for id in subset where !successes.contains(id) && !result.failures.contains(where: { $0.itemID == id }) {
                    result.failures.append(.init(key: "Xcode Cleaner Remove Failed", itemID: id, mayHaveRemovedContents: true))
                }
            } catch {
                result.failures += subset.map { CleanerFailure.wrapping(error).scoped(to: $0, partial: true) }
            }
        }
        return result
    }
}
#endif
