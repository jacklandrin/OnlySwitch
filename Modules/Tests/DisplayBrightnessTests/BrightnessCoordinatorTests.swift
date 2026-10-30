import Testing
@testable import DisplayBrightness

@MainActor
struct BrightnessCoordinatorTests {
    @Test func writesOnlyRequestedScreenAndKeepsFailureSeparate() async throws {
        var writes: [UInt32] = []
        let coordinator = BrightnessCoordinator(settings: .init(smoothTransitions: false), write: { id, _ in
            writes.append(id); return id != 2
        })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .native, level: 1), .init(id: 2, name: "Two", control: .ddc, level: 1)])
        try await coordinator.apply(.init(screenID: 1, generation: coordinator.snapshot.generation, level: 0.5, revision: 1))
        await #expect(throws: BrightnessError.writeFailed) {
            try await coordinator.apply(.init(screenID: 2, generation: coordinator.snapshot.generation, level: 0.2, revision: 1))
        }
        #expect(writes == [1, 2])
        #expect(coordinator.snapshot.displays[1].level == 0.2)
        #expect(coordinator.snapshot.displays[1].appliedLevel == 1)
        #expect(coordinator.snapshot.displays[1].error)
    }
    @Test func obsoleteTopologyNeverWrites() async {
        var count = 0
        let coordinator = BrightnessCoordinator(write: { _, _ in count += 1; return true })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .native, level: 1)])
        let generation = coordinator.snapshot.generation
        coordinator.replaceInventory([])
        await #expect(throws: BrightnessError.staleRequest) {
            try await coordinator.apply(.init(screenID: 1, generation: generation, level: 0, revision: 1))
        }
        #expect(count == 0)
    }
    @Test func settingChangeRemovesUnsafeSoftwareBlack() async throws {
        var outputs: [BrightnessOutput] = []
        let coordinator = BrightnessCoordinator(settings: .init(smoothTransitions: false, allowZeroSoftwareBrightness: true), write: { _, output in outputs.append(output); return true })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .software, level: 1)])
        try await coordinator.apply(.init(screenID: 1, generation: coordinator.snapshot.generation, level: 0, revision: 1))
        await coordinator.updateSettings(.init(smoothTransitions: false))
        #expect(outputs.last?.software == 0.1)
    }
    @Test func newerIntentInvalidatesSuspendedTransition() async throws {
        let gate = BrightnessSleepGate()
        var outputs: [Double] = []
        let coordinator = BrightnessCoordinator(write: { _, output in
            outputs.append(output.hardware ?? 1); return true
        }, sleep: { _ in await gate.wait() })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .native, level: 1)])
        let generation = coordinator.snapshot.generation
        let old = Task { try await coordinator.apply(.init(screenID: 1, generation: generation, level: 0.2, revision: 1)) }
        var iterator = gate.entered.makeAsyncIterator()
        _ = await iterator.next()
        await coordinator.updateSettings(.init(smoothTransitions: false))
        try await coordinator.apply(.init(screenID: 1, generation: generation, level: 0.6, revision: 2))
        await gate.release()
        await #expect(throws: BrightnessError.staleRequest) { try await old.value }
        #expect(outputs.last == 0.6)
        coordinator.observeNative(id: 1, level: 0.7)
        #expect(coordinator.snapshot.displays[0].level == 0.7)
    }

    @Test func reorderedIntentCannotSupersedeNewerRevision() async throws {
        let coordinator = BrightnessCoordinator(settings: .init(smoothTransitions: false), write: { _, _ in true })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .native, level: 1)])
        try await coordinator.apply(.init(screenID: 1, generation: coordinator.snapshot.generation, level: 0.6, revision: 2))
        await #expect(throws: BrightnessError.staleRequest) {
            try await coordinator.apply(.init(screenID: 1, generation: coordinator.snapshot.generation, level: 0.2, revision: 1))
        }
        #expect(coordinator.snapshot.displays[0].appliedLevel == 0.6)
    }

    @Test func settingsReconciliationDoesNotOverwriteNewerIntentOnAnotherScreen() async throws {
        let gate = BrightnessSleepGate()
        var shouldSuspend = true
        let coordinator = BrightnessCoordinator(settings: .init(smoothTransitions: false), write: { id, _ in
            if id == 1 && shouldSuspend { shouldSuspend = false; await gate.wait() }
            return true
        })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .native, level: 1), .init(id: 2, name: "Two", control: .native, level: 1)])
        let reconcile = Task { await coordinator.updateSettings(.init(smoothTransitions: false, combinedDimming: false)) }
        var iterator = gate.entered.makeAsyncIterator(); _ = await iterator.next()
        try await coordinator.apply(.init(screenID: 2, generation: coordinator.snapshot.generation, level: 0.6, revision: 1))
        await gate.release(); await reconcile.value
        #expect(coordinator.snapshot.displays[1].appliedLevel == 0.6)
    }

    @Test func nativeSyncIgnoresOwnWritesAndInvalidatesOverlappingCycles() {
        var state = BrightnessNativeSyncState()
        let first = state.beginCycle()
        #expect(state.observe(id: 1, level: 0.5) == false)
        state.recordOwnWrite(id: 1, level: 0.6)
        #expect(state.observe(id: 1, level: 0.6) == false)
        let changed = state.observe(id: 1, level: 0.7)
        #expect(changed)
        let smallChange = state.observe(id: 1, level: 0.703)
        #expect(smallChange == false)
        let cumulativeChange = state.observe(id: 1, level: 0.706)
        #expect(cumulativeChange)
        #expect(state.isCurrent(first))
        let second = state.beginCycle()
        #expect(state.isCurrent(first) == false)
        #expect(state.isCurrent(second))
        state.invalidate()
        #expect(state.isCurrent(second) == false)
        #expect(state.observe(id: 1, level: 0.2) == false)
    }

    @Test func resetDoesNotOverwriteNewerIntentOnAnotherScreen() async throws {
        let gate = BrightnessSleepGate()
        var shouldSuspend = true
        let coordinator = BrightnessCoordinator(settings: .init(smoothTransitions: false), write: { id, _ in
            if id == 1 && shouldSuspend { shouldSuspend = false; await gate.wait() }
            return true
        })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .software, level: 0.2), .init(id: 2, name: "Two", control: .software, level: 0.3)])
        let reset = Task { await coordinator.resetSoftwareDimming() }
        var iterator = gate.entered.makeAsyncIterator(); _ = await iterator.next()
        try await coordinator.apply(.init(screenID: 2, generation: coordinator.snapshot.generation, level: 0.6, revision: 1))
        await gate.release(); await reset.value
        #expect(coordinator.snapshot.displays[1].appliedLevel == 0.6)
    }
    @Test func topologyChangeDuringWriteDoesNotRestoreAnOldScreen() async {
        let gate = BrightnessSleepGate()
        let coordinator = BrightnessCoordinator(settings: .init(smoothTransitions: false), write: { _, _ in await gate.wait(); return true })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .software, level: 1)])
        let request = BrightnessRequest(screenID: 1, generation: coordinator.snapshot.generation, level: 0.2, revision: 1)
        let write = Task { try await coordinator.apply(request) }
        var iterator = gate.entered.makeAsyncIterator(); _ = await iterator.next()
        coordinator.replaceInventory([])
        await gate.release()
        await #expect(throws: BrightnessError.staleRequest) { try await write.value }
        #expect(coordinator.snapshot.displays.isEmpty)
    }

    @Test func internalIntentMarksTheAcceptedUIRevisionAndANewerUIIntentClearsIt() async throws {
        let coordinator = BrightnessCoordinator(settings: .init(smoothTransitions: false), write: { _, _ in true })
        coordinator.replaceInventory([.init(id: 1, name: "One", control: .native, level: 1)])
        let generation = coordinator.snapshot.generation
        try await coordinator.apply(.init(screenID: 1, generation: generation, level: 0.2, revision: 1))
        #expect(coordinator.snapshot.displays[0].supersededUIRevision == 0)
        try await coordinator.apply(.init(screenID: 1, generation: generation, level: 0.3, revision: 0))
        #expect(coordinator.snapshot.displays[0].supersededUIRevision == 1)
        try await coordinator.apply(.init(screenID: 1, generation: generation, level: 0.6, revision: 2))
        #expect(coordinator.snapshot.displays[0].supersededUIRevision == 0)
        #expect(coordinator.snapshot.displays[0].appliedLevel == 0.6)
    }

}


private actor BrightnessSleepGate {
    nonisolated let entered: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var waiting: CheckedContinuation<Void, Never>?
    init() {
        let pair = AsyncStream<Void>.makeStream()
        entered = pair.stream; continuation = pair.continuation
    }
    func wait() async {
        await withCheckedContinuation { waiting = $0; continuation.yield(()) }
    }
    func release() { waiting?.resume(); waiting = nil }
}
