import ComposableArchitecture
import Foundation
import Testing
@testable import DesktopPet

@MainActor
struct DesktopPetAgentActivityTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func repeatedStartHasOneSubscriptionAndStopRejectsOldGeneration() async {
        let calls = LockIsolated(0)
        let (stream, continuation) = AsyncStream.makeStream(of: DesktopPetAgentUpdate.self)
        let store = TestStore(initialState: DesktopPetAgentActivityFeature.State()) {
            DesktopPetAgentActivityFeature()
        } withDependencies: {
            $0.desktopPetAgentActivity.updates = {
                calls.withValue { $0 += 1 }
                return stream
            }
        }
        await store.send(.start) {
            $0.isEnabled = true
            $0.generation = 1
        }
        let first = event(.started)
        continuation.yield(.init(events: [first], date: now))
        await store.receive(.updated(.init(events: [first], date: now), generation: 1)) {
            $0.runningTasks["codex-a"] = running()
        }
        await store.send(.start)
        #expect(calls.value == 1)
        await store.send(.stop) {
            $0 = .init()
            $0.generation = 2
        }
        await store.send(.updated(.init(events: [event(.completed)], date: now), generation: 1))
        continuation.finish()
        await store.finish()
    }

    @Test func concurrentAgentsKeepWorkingWhenOneCompletes() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        await store.send(update([
            event(.started), event(.started, agent: .claude, session: "claude-a", turn: nil)
        ])) {
            $0.runningTasks["codex-a"] = running()
            $0.runningTasks["claude-a"] = running(agent: .claude, turn: nil)
        }
        #expect(store.state.runningAgents == [.codex, .claude])
        #expect(store.state.showsStatus == false)
        #expect(DesktopPetMetrics.canvasSize(for: nil, showsAgentStatus: store.state.showsStatus) == DesktopPetMetrics.canvasSize)
        await store.send(update([event(.completed, id: "done-a")])) {
            $0.runningTasks["codex-a"] = nil
            $0.completion = .init(id: "codex-a:done-a", agent: .codex)
            $0.completedIDs = ["codex-a:done-a"]
        }
        #expect(store.state.runningAgents == [.claude])
        #expect(store.state.showsStatus)
        #expect(DesktopPetMetrics.canvasSize(for: nil, showsAgentStatus: store.state.showsStatus).width == 308)
        await store.send(.dismissCompletion(id: "codex-a:done-a")) { $0.completion = nil }
        #expect(store.state.runningAgents == [.claude])
        #expect(store.state.showsStatus == false)
        #expect(DesktopPetMetrics.canvasSize(for: nil, showsAgentStatus: store.state.showsStatus) == DesktopPetMetrics.canvasSize)
        await store.finish()
    }

    @Test func fastTaskCompletesOnceAndDuplicateEndDoesNotRepeatBubble() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        await store.send(update([event(.started), event(.completed, id: "done-a")])) {
            $0.completion = .init(id: "codex-a:done-a", agent: .codex)
            $0.completedIDs = ["codex-a:done-a"]
        }
        await store.send(update([event(.completed, id: "done-a")]))
        await store.send(.dismissCompletion(id: "codex-a:done-a")) { $0.completion = nil }
        await store.send(update([event(.completed, id: "done-a")]))
        await store.finish()
    }

    @Test func historicalCompletionAndUnobservedCompletionStaySilent() async {
        let store = makeStore()
        await store.send(update([event(.completed, id: "unobserved")]))
        await store.send(update([
            event(.started, historical: true), event(.completed, id: "old", historical: true)
        ]))
        #expect(store.state.showsStatus == false)
    }

    @Test(arguments: [DesktopPetAgentEvent.Kind.stopped, .unavailable])
    func failedOrMissingSessionNeverProducesSuccess(kind: DesktopPetAgentEvent.Kind) async {
        let store = makeStore()
        await store.send(update([event(.started)])) { $0.runningTasks["codex-a"] = running() }
        await store.send(update([event(kind)])) { $0.runningTasks["codex-a"] = nil }
        #expect(store.state.completion == nil)
    }

    @Test func endFromDifferentTurnDoesNotStopCurrentTask() async {
        let store = makeStore()
        await store.send(update([event(.started)])) { $0.runningTasks["codex-a"] = running() }
        await store.send(update([event(.completed, turn: "older-turn", id: "older-end")]))
        #expect(store.state.runningAgents == [.codex])
    }

    @Test func laterProgressTimestampDoesNotLoseEarlierCompletion() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        await store.send(update([event(.started)])) { $0.runningTasks["codex-a"] = running() }
        await store.send(update([event(.activity, offset: 5)], offset: 5)) {
            $0.runningTasks["codex-a"]?.lastActivity = now.addingTimeInterval(5)
        }
        await store.send(update([event(.completed, id: "done-a", offset: 2)], offset: 6)) {
            $0.runningTasks["codex-a"] = nil
            $0.completion = .init(id: "codex-a:done-a", agent: .codex)
            $0.completedIDs = ["codex-a:done-a"]
        }
        await store.send(.dismissCompletion(id: "codex-a:done-a")) { $0.completion = nil }
        await store.finish()
    }

    @Test func partialLogCompletionSurvivesLaterFilesystemActivityEndToEnd() async throws {
        let fixture = try AgentLogFixture()
        let baseline = Date(timeIntervalSince1970: 1_794_657_600)
        let start = "{\"timestamp\":\"2026-11-14T12:00:01Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-a\"}}\n"
        let end = "{\"timestamp\":\"2026-11-14T12:00:02Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"turn-a\"}}"
        try fixture.write(start + end, modified: baseline.addingTimeInterval(5))
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: baseline)
        let initial = await monitor.scan(at: baseline.addingTimeInterval(5))
        let store = makeStore()
        let started = try #require(initial.events.first { $0.kind == .started })
        let path = started.sessionID
        await store.send(.updated(initial, generation: 0)) {
            $0.runningTasks[path] = .init(
                agent: .codex, turnID: "turn-a", startedAt: baseline.addingTimeInterval(1),
                lastActivity: baseline.addingTimeInterval(1)
            )
        }
        try fixture.append("\n", modified: baseline.addingTimeInterval(6))
        let final = await monitor.scan(at: baseline.addingTimeInterval(6))
        let completion = try #require(final.events.first { $0.kind == .completed })
        let id = "\(path):\(completion.id)"
        await store.send(.updated(final, generation: 0)) {
            $0.runningTasks = [:]
            $0.completion = .init(id: id, agent: .codex)
            $0.completedIDs = [id]
        }
        await store.send(.dismissCompletion(id: id)) { $0.completion = nil }
        await store.finish()
    }

    @Test func oldClaudeStartWithFreshFilesystemMetadataRemainsIdle() async throws {
        let fixture = try AgentLogFixture()
        let baseline = Date(timeIntervalSince1970: 1_794_657_600)
        let file = fixture.roots.claude.appendingPathComponent("project/session.jsonl")
        let oldStart = "{\"timestamp\":\"2026-11-13T15:00:00Z\",\"type\":\"user\",\"uuid\":\"old-prompt\",\"message\":{\"content\":\"Earlier task\"}}\n"
        try fixture.write(oldStart, to: file, modified: baseline)
        let monitor = DesktopPetAgentLogMonitor(roots: fixture.roots, startedAt: baseline)
        let store = makeStore()
        let initial = await monitor.scan(at: baseline)
        await store.send(.updated(initial, generation: 0))
        #expect(store.state.runningAgents.isEmpty)

        let metadata = "{\"timestamp\":\"2026-11-14T12:00:01Z\",\"type\":\"system\",\"subtype\":\"informational\"}\n"
        try fixture.append(metadata, to: file, modified: baseline.addingTimeInterval(1))
        let appended = await monitor.scan(at: baseline.addingTimeInterval(1))
        #expect(appended.events.isEmpty)
        await store.send(.updated(appended, generation: 0))
        #expect(store.state.showsStatus == false)
    }

    @Test func genuineRecentProgressKeepsAnOlderLongTaskWorking() async {
        let store = makeStore()
        await store.send(update([
            event(.started, agent: .claude, session: "claude-a", turn: nil, offset: -3_600, historical: true),
            event(.activity, agent: .claude, session: "claude-a", turn: nil, offset: -5, historical: true)
        ])) {
            $0.runningTasks["claude-a"] = .init(
                agent: .claude, turnID: nil, startedAt: now.addingTimeInterval(-3_600),
                lastActivity: now.addingTimeInterval(-5)
            )
        }
        #expect(store.state.runningAgents == [.claude])
        #expect(store.state.completion == nil)
    }

    @Test func silentSessionExpiresWithoutSuccess() async {
        let store = makeStore()
        await store.send(update([event(.started)])) { $0.runningTasks["codex-a"] = running() }
        await store.send(update([], offset: DesktopPetAgentActivityFeature.activityLifetime + 1)) {
            $0.runningTasks = [:]
        }
        #expect(store.state.completion == nil)
    }

    @Test func completionQueueWaitsEightSecondsAndIgnoresOldDismissal() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        let first = DesktopPetAgentCompletion(id: "codex-a:done-a", agent: .codex)
        let second = DesktopPetAgentCompletion(id: "claude-a:done-b", agent: .claude)
        await store.send(update([
            event(.started), event(.completed, id: "done-a"),
            event(.started, agent: .claude, session: "claude-a", turn: nil),
            event(.completed, agent: .claude, session: "claude-a", turn: nil, id: "done-b")
        ])) {
            $0.completion = first
            $0.queuedCompletions = [second]
            $0.completedIDs = [first.id, second.id]
        }
        await clock.advance(by: .seconds(8))
        await store.receive(.dismissCompletion(id: first.id)) {
            $0.completion = second
            $0.queuedCompletions = []
        }
        await store.send(.dismissCompletion(id: first.id))
        #expect(store.state.completion == second)
        await clock.advance(by: .seconds(8))
        await store.receive(.dismissCompletion(id: second.id)) { $0.completion = nil }
        await store.finish()
    }

    @Test func stopCancelsPendingCompletionAndRestartRejectsOldUpdates() async {
        let clock = TestClock()
        let store = makeStore(clock: clock)
        await store.send(update([event(.started), event(.completed, id: "done-a")])) {
            $0.completion = .init(id: "codex-a:done-a", agent: .codex)
            $0.completedIDs = ["codex-a:done-a"]
        }
        await store.send(.stop) {
            $0 = .init()
            $0.generation = 1
        }
        await store.send(.start) {
            $0.isEnabled = true
            $0.generation = 2
        }
        await store.send(update([event(.started)]))
        await clock.advance(by: .seconds(8))
        await store.finish()
    }

    private func makeStore(clock: TestClock<Duration> = TestClock()) -> TestStoreOf<DesktopPetAgentActivityFeature> {
        var initial = DesktopPetAgentActivityFeature.State()
        initial.isEnabled = true
        return TestStore(initialState: initial) {
            DesktopPetAgentActivityFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
    }

    private func running(agent: DesktopPetAgent = .codex, turn: String? = "turn-a") -> DesktopPetAgentActivityFeature.RunningTask {
        .init(agent: agent, turnID: turn, startedAt: now, lastActivity: now)
    }

    private func update(_ events: [DesktopPetAgentEvent], offset: TimeInterval = 0) -> DesktopPetAgentActivityFeature.Action {
        .updated(.init(events: events, date: now.addingTimeInterval(offset)), generation: 0)
    }

    private func event(
        _ kind: DesktopPetAgentEvent.Kind,
        agent: DesktopPetAgent = .codex,
        session: String = "codex-a",
        turn: String? = "turn-a",
        id: String = "event-a",
        offset: TimeInterval = 0,
        historical: Bool = false
    ) -> DesktopPetAgentEvent {
        .init(agent: agent, sessionID: session, turnID: turn, id: id, date: now.addingTimeInterval(offset), kind: kind, isHistorical: historical)
    }
}
