import ComposableArchitecture
import Foundation
import Testing
@testable import OnlyAgent

/// The password typed by the user goes straight to the run's askpass channel
/// and is never kept in reducer state.
@MainActor
struct AgentPasswordFlowTests {
    private struct Harness {
        let answers = LockIsolated<[String?]>([])
        let continuation: AsyncThrowingStream<AgentRunEvent, Error>.Continuation
        let stream: AsyncThrowingStream<AgentRunEvent, Error>

        init() {
            (stream, continuation) = AsyncThrowingStream<AgentRunEvent, Error>.makeStream()
        }
    }

    private static let request = AgentPasswordRequest(id: UUID(99), prompt: "Password:")

    private func makeStore(_ harness: Harness, plan: AgentPlan) -> TestStoreOf<AgentConversationReducer> {
        let stream = harness.stream
        let continuation = harness.continuation
        let answers = harness.answers
        return TestStore(initialState: .fixture(messages: [AgentFixtures.planMessage(plan)])) {
            AgentConversationReducer()
        } withDependencies: {
            $0.agentConversationClient.run = { _, _ in stream }
            $0.agentConversationClient.answerPassword = { _, password in
                answers.withValue { $0.append(password) }
                if password != nil {
                    continuation.yield(.finished("done"))
                    continuation.finish()
                } else {
                    continuation.finish(throwing: AgentScriptError(message: "Password entry was cancelled."))
                }
            }
        }
    }

    @Test
    func passwordRequestIsShownAndAnswerIsForwarded() async {
        let harness = Harness()
        let plan = AgentPlan(id: UUID(10), title: "Upgrade", summary: "", steps: [
            AgentScriptStep(id: UUID(11), title: "brew", kind: .shell, code: "brew upgrade"),
        ])
        let store = makeStore(harness, plan: plan)

        await store.send(.runPlan(plan.id)) {
            $0.runningPlanID = plan.id
            $0.updatePlan(plan.id) { $0.steps[0].status = .running }
        }
        harness.continuation.yield(.passwordRequested(Self.request))
        await store.receive(\.passwordRequested) {
            $0.passwordRequest = Self.request
        }
        await store.send(.passwordSubmitted("s3cret")) {
            $0.passwordRequest = nil
        }
        await store.receive(\.stepFinished) {
            $0.runningPlanID = nil
            $0.updatePlan(plan.id) {
                $0.steps[0].status = .succeeded
                $0.steps[0].output = "done"
            }
        }
        #expect(harness.answers.value == ["s3cret"])
    }

    @Test
    func cancellingPasswordFailsTheStep() async {
        let harness = Harness()
        let plan = AgentPlan(id: UUID(10), title: "Upgrade", summary: "", steps: [
            AgentScriptStep(id: UUID(11), title: "brew", kind: .shell, code: "brew upgrade"),
            AgentScriptStep(id: UUID(12), title: "next", kind: .shell, code: "true"),
        ])
        let store = makeStore(harness, plan: plan)

        await store.send(.runPlan(plan.id)) {
            $0.runningPlanID = plan.id
            $0.updatePlan(plan.id) { $0.steps[0].status = .running }
        }
        harness.continuation.yield(.passwordRequested(Self.request))
        await store.receive(\.passwordRequested) {
            $0.passwordRequest = Self.request
        }
        await store.send(.passwordCancelled) {
            $0.passwordRequest = nil
        }
        await store.receive(\.stepFinished) {
            $0.runningPlanID = nil
            $0.updatePlan(plan.id) {
                $0.steps[0].status = .failed
                $0.steps[0].error = "Password entry was cancelled."
                $0.steps[1].status = .skipped
            }
        }
        #expect(harness.answers.value == [nil])
    }

    @Test
    func stoppingWhilePasswordIsPendingAnswersNil() async {
        let harness = Harness()
        let plan = AgentPlan(id: UUID(10), title: "Upgrade", summary: "", steps: [
            AgentScriptStep(id: UUID(11), title: "brew", kind: .shell, code: "brew upgrade"),
        ])
        let store = makeStore(harness, plan: plan)

        await store.send(.runPlan(plan.id)) {
            $0.runningPlanID = plan.id
            $0.updatePlan(plan.id) { $0.steps[0].status = .running }
        }
        harness.continuation.yield(.passwordRequested(Self.request))
        await store.receive(\.passwordRequested) {
            $0.passwordRequest = Self.request
        }
        await store.send(.stopRun) {
            $0.passwordRequest = nil
            $0.runningPlanID = nil
            $0.updatePlan(plan.id) { $0.steps[0].status = .stopped }
        }
        await store.finish()
        #expect(harness.answers.value == [nil])
    }

    @Test
    func passwordRequestFromAnotherPlanIsIgnored() async {
        let harness = Harness()
        let plan = AgentFixtures.plan()
        let store = makeStore(harness, plan: plan)
        await store.send(.passwordRequested(planID: UUID(1234), request: Self.request))
    }
}
