#if os(macOS)
import Foundation
import Testing
@testable import XcodeCleaner

struct XcodeCleanerClientTests {
    let fileA = CleanerItem(id: "file:a", category: .derivedData, title: "A", bytes: 1)
    let fileB = CleanerItem(id: "file:b", category: .spmCaches, title: "B", bytes: 2)
    let device = CleanerItem(id: "device:a", category: .simulatorDevice, title: "Phone", bytes: nil)

    @Test func mixedBatchDeduplicatesAndDispatchesEachAdapterOnce() async throws {
        let files = CleanerSnapshot(items: [fileA, fileB]), sims = CleanerSnapshot(items: [device])
        let fileRecorder = CleanerBatchRecorder(), simRecorder = CleanerBatchRecorder()
        let coordinator = CleanerCoordinator(
            filesystem: .init(scan: { files }, clean: { request in await fileRecorder.record(request); return .init(removedItemIDs: request.itemIDs) }),
            simulator: .init(scan: { sims }, clean: { request in await simRecorder.record(request); return .init(removedItemIDs: request.itemIDs) })
        )
        let snapshot = try await coordinator.scan()
        await coordinator.activateSnapshot(snapshot.id)
        let result = try await coordinator.clean(.init(snapshotID: snapshot.id, itemIDs: [fileA.id, device.id, fileB.id, fileA.id]))
        #expect(Set(result.removedItemIDs) == [fileA.id, fileB.id, device.id])
        #expect(await fileRecorder.requests == [.init(snapshotID: files.id, itemIDs: [fileA.id, fileB.id])])
        #expect(await simRecorder.requests == [.init(snapshotID: sims.id, itemIDs: [device.id])])
    }

    @Test func disabledAndUnknownIDsFailWithoutPreventingOtherAdapterSuccess() async throws {
        var disabled = fileB; disabled.canClean = false
        let files = CleanerSnapshot(items: [fileA, disabled]), sims = CleanerSnapshot(items: [device])
        let recorder = CleanerBatchRecorder()
        let coordinator = CleanerCoordinator(
            filesystem: .init(scan: { files }, clean: { request in await recorder.record(request); return .init(failures: [.init(key: "denied", itemID: request.itemIDs.first)]) }),
            simulator: .init(scan: { sims }, clean: { request in .init(removedItemIDs: request.itemIDs) })
        )
        let snapshot = try await coordinator.scan()
        let result = try await coordinator.clean(.init(snapshotID: snapshot.id, itemIDs: [disabled.id, "unknown", fileA.id, device.id]))
        #expect(result.removedItemIDs == [device.id])
        #expect(Set(result.failures.compactMap(\.itemID)) == [disabled.id, "unknown", fileA.id])
        #expect(await recorder.requests.first?.itemIDs == [fileA.id])
    }

    @Test func activeAuthorizationSurvivesNewCandidatesAndConcurrentCleanupIsRejected() async throws {
        let heldClean = CleanerAsyncGate<CleanerCleanupResult>()
        let recorder = CleanerBatchRecorder()
        let file = fileA
        let coordinator = CleanerCoordinator(
            filesystem: .init(scan: { CleanerSnapshot(items: [file]) }, clean: { request in await recorder.record(request); return await heldClean.value() }),
            simulator: .init(scan: { CleanerSnapshot() }, clean: { _ in .init() }),
            retainedCandidateLimit: 2
        )
        let displayed = try await coordinator.scan()
        await coordinator.activateSnapshot(displayed.id)
        let oldestCandidate = try await coordinator.scan()
        for _ in 0..<5 { _ = try await coordinator.scan() }
        let evicted = try await coordinator.clean(.init(snapshotID: oldestCandidate.id, itemIDs: [file.id]))
        #expect(!evicted.failures.isEmpty)
        #expect(await recorder.requests.isEmpty)
        let first = Task { try await coordinator.clean(.init(snapshotID: displayed.id, itemIDs: [file.id])) }
        await heldClean.waitUntilRequested()
        let overlapping = try await coordinator.clean(.init(snapshotID: displayed.id, itemIDs: [file.id]))
        #expect(!overlapping.failures.isEmpty)
        #expect(await recorder.requests.count == 1)
        await heldClean.resolve(.init(removedItemIDs: [file.id]))
        #expect(try await first.value.removedItemIDs == [file.id])
    }

    @Test func cleanupOfDisplayedSnapshotCanInterleaveHeldRefreshWithoutLosingAuthorization() async throws {
        let gate = CleanerAsyncGate<CleanerSnapshot>()
        let files = CleanerSnapshot(items: [fileA])
        let sequence = CleanerScanSequence(first: CleanerSnapshot(items: [device]), gate: gate)
        let coordinator = CleanerCoordinator(
            filesystem: .init(scan: { files }, clean: { request in .init(removedItemIDs: request.itemIDs) }),
            simulator: .init(scan: { await sequence.scan() }, clean: { request in .init(removedItemIDs: request.itemIDs) })
        )
        let displayed = try await coordinator.scan()
        await coordinator.activateSnapshot(displayed.id)
        let refresh = Task { try await coordinator.scan() }
        await gate.waitUntilRequested()
        let result = try await coordinator.clean(.init(snapshotID: displayed.id, itemIDs: [fileA.id, device.id]))
        #expect(Set(result.removedItemIDs) == [fileA.id, device.id])
        await gate.resolve(CleanerSnapshot(items: [device]))
        _ = try? await refresh.value
        let next = try await coordinator.clean(.init(snapshotID: displayed.id, itemIDs: [fileA.id]))
        #expect(next.removedItemIDs == [fileA.id])
    }

    @Test func inventoryStartedDuringHeldCleanupCannotPublishHalfMutatedState() async throws {
        let gate = CleanerAsyncGate<CleanerCleanupResult>()
        let files = CleanerSnapshot(items: [fileA])
        let coordinator = CleanerCoordinator(
            filesystem: .init(scan: { files }, clean: { _ in await gate.value() }),
            simulator: .init(scan: { CleanerSnapshot() }, clean: { _ in .init() })
        )
        let snapshot = try await coordinator.scan()
        let operation = Task { try await coordinator.clean(.init(snapshotID: snapshot.id, itemIDs: [fileA.id])) }
        await gate.waitUntilRequested()
        do {
            _ = try await coordinator.scan()
            Issue.record("An inventory started during destructive work must not publish")
        } catch is CancellationError {} catch { Issue.record("Expected cancellation, received \(error)") }
        await gate.resolve(.init(removedItemIDs: [fileA.id]))
        #expect(try await operation.value.removedItemIDs == [fileA.id])
    }

    @Test func laterAdapterCancellationDoesNotDiscardEarlierConfirmedSuccess() async throws {
        let files = CleanerSnapshot(items: [fileA]), sims = CleanerSnapshot(items: [device])
        let coordinator = CleanerCoordinator(
            filesystem: .init(scan: { files }, clean: { request in .init(removedItemIDs: request.itemIDs) }),
            simulator: .init(scan: { sims }, clean: { _ in throw CancellationError() })
        )
        let snapshot = try await coordinator.scan()
        let result = try await coordinator.clean(.init(snapshotID: snapshot.id, itemIDs: [fileA.id, device.id]))
        #expect(result.removedItemIDs == [fileA.id])
        #expect(result.failures.contains { $0.itemID == device.id })
    }

    @Test func newerDisplayedCandidateCanCleanBeforeActivationAcknowledgementAndOldAcknowledgementCannotRegressIt() async throws {
        let file = fileA
        let recorder = CleanerBatchRecorder()
        let coordinator = CleanerCoordinator(
            filesystem: .init(scan: { CleanerSnapshot(items: [file]) }, clean: { request in await recorder.record(request); return .init(removedItemIDs: request.itemIDs) }),
            simulator: .init(scan: { CleanerSnapshot() }, clean: { _ in .init() })
        )
        let first = try await coordinator.scan()
        await coordinator.activateSnapshot(first.id)
        let displayed = try await coordinator.scan()
        // The reducer has accepted this candidate, but its asynchronous pin effect has not run yet.
        let firstResult = try await coordinator.clean(.init(snapshotID: displayed.id, itemIDs: [file.id]))
        #expect(firstResult.removedItemIDs == [file.id])
        await coordinator.activateSnapshot(first.id)
        let secondResult = try await coordinator.clean(.init(snapshotID: displayed.id, itemIDs: [file.id]))
        #expect(secondResult.removedItemIDs == [file.id])
        #expect(await recorder.requests.count == 2)
    }
}

private actor CleanerScanSequence {
    let first: CleanerSnapshot
    let gate: CleanerAsyncGate<CleanerSnapshot>
    var calls = 0
    init(first: CleanerSnapshot, gate: CleanerAsyncGate<CleanerSnapshot>) { self.first = first; self.gate = gate }
    func scan() async -> CleanerSnapshot {
        calls += 1
        if calls == 1 { return first }
        return await gate.value()
    }
}
#endif
