import ComposableArchitecture
import Foundation
import Testing
@testable import OnlyAgent

@MainActor
struct AgentConversationExecutionTests {
    @Test
    func runsStepsInOrder() async {
        let calls = LockIsolated<[String]>([])
        let plan = AgentFixtures.plan()
        let store = TestStore(initialState: .fixture(messages: [AgentFixtures.planMessage(plan)])) {
            AgentConversationReducer()
        } withDependencies: {
            $0.agentConversationClient.run = agentRun { kind, code in
                calls.withValue { $0.append("\(kind.rawValue):\(code)") }
                return "ok"
            }
        }

        await store.send(.runPlan(plan.id)) {
            $0.runningPlanID = plan.id
            $0.updatePlan(plan.id) { $0.steps[0].status = .running }
        }
        await store.receive(\.stepFinished) {
            $0.updatePlan(plan.id) {
                $0.steps[0].status = .succeeded
                $0.steps[0].output = "ok"
                $0.steps[1].status = .running
            }
        }
        await store.receive(\.stepFinished) {
            $0.runningPlanID = nil
            $0.updatePlan(plan.id) {
                $0.steps[1].status = .succeeded
                $0.steps[1].output = "ok"
            }
        }
        #expect(calls.value == ["applescript:tell dark", "shell:echo loud"])
    }

    @Test
    func failureStopsAndSkipsRemainingSteps() async {
        let calls = LockIsolated(0)
        let plan = AgentFixtures.plan()
        let store = TestStore(initialState: .fixture(messages: [AgentFixtures.planMessage(plan)])) {
            AgentConversationReducer()
        } withDependencies: {
            $0.agentConversationClient.run = agentRun { _, _ in
                calls.withValue { $0 += 1 }
                throw TestFailure(message: "denied")
            }
        }

        await store.send(.runPlan(plan.id)) {
            $0.runningPlanID = plan.id
            $0.updatePlan(plan.id) { $0.steps[0].status = .running }
        }
        await store.receive(\.stepFinished) {
            $0.runningPlanID = nil
            $0.updatePlan(plan.id) {
                $0.steps[0].status = .failed
                $0.steps[0].error = "denied"
                $0.steps[1].status = .skipped
            }
        }
        #expect(calls.value == 1)
    }

    @Test
    func cannotSaveUnsuccessfulPlan() async {
        let plan = AgentFixtures.plan(statuses: [.succeeded, .failed])
        let store = TestStore(initialState: .fixture(messages: [AgentFixtures.planMessage(plan)])) {
            AgentConversationReducer()
        }
        await store.send(.saveTapped(plan.id))
    }

    @Test
    func savingSucceededPlanComposesCommand() async {
        let saved = LockIsolated<[AgentEvolutionDraft]>([])
        let clock = TestClock()
        let plan = AgentFixtures.plan(statuses: [.succeeded, .succeeded])
        let store = TestStore(initialState: .fixture(messages: [AgentFixtures.planMessage(plan)])) {
            AgentConversationReducer()
        } withDependencies: {
            $0.continuousClock = clock
            $0.agentEvolutionClient.saveButton = { draft in saved.withValue { $0.append(draft) } }
        }

        await store.send(.saveTapped(plan.id)) {
            $0.saveDraft = .init(planID: plan.id, name: "Dark and loud")
        }
        await store.send(.saveNameChanged("Night")) {
            $0.saveDraft?.name = "Night"
        }
        await store.send(.saveConfirmed) {
            $0.saveDraft?.isSaving = true
        }
        await store.receive(\.saveFinished) {
            $0.saveDraft = nil
            $0.savedPlanIDs = [plan.id]
            $0.toast = .savedToEvolution
        }
        await clock.advance(by: .seconds(2))
        await store.receive(\.toastDismissed) {
            $0.toast = nil
        }
        #expect(saved.value == [AgentEvolutionDraft(
            name: "Night",
            command: "run script \"tell dark\"\ndo shell script \"echo loud\""
        )])
    }

    @Test
    func saveFailureKeepsSheetWithError() async {
        let plan = AgentFixtures.plan(statuses: [.succeeded, .succeeded])
        var state = AgentConversationReducer.State.fixture(messages: [AgentFixtures.planMessage(plan)])
        state.saveDraft = .init(planID: plan.id, name: "Night")
        let store = TestStore(initialState: state) {
            AgentConversationReducer()
        } withDependencies: {
            $0.agentEvolutionClient.saveButton = { _ in throw TestFailure(message: "disk full") }
        }

        await store.send(.saveConfirmed) {
            $0.saveDraft?.isSaving = true
        }
        await store.receive(\.saveFinished) {
            $0.saveDraft?.isSaving = false
            $0.saveDraft?.error = "disk full"
        }
    }

    @Test
    func blankNameCannotBeSaved() async {
        let plan = AgentFixtures.plan(statuses: [.succeeded, .succeeded])
        var state = AgentConversationReducer.State.fixture(messages: [AgentFixtures.planMessage(plan)])
        state.saveDraft = .init(planID: plan.id, name: "  ")
        let store = TestStore(initialState: state) {
            AgentConversationReducer()
        }
        await store.send(.saveConfirmed)
    }

    @Test
    func editingCodeResetsStatusesSoPlanMustRerun() async {
        let plan = AgentFixtures.plan(statuses: [.succeeded, .succeeded])
        let store = TestStore(initialState: .fixture(messages: [AgentFixtures.planMessage(plan)])) {
            AgentConversationReducer()
        }
        await store.send(.editStepCode(planID: plan.id, stepID: UUID(12), code: "echo louder")) {
            $0.updatePlan(plan.id) {
                $0.steps[0].status = .pending
                $0.steps[1].status = .pending
                $0.steps[1].code = "echo louder"
            }
        }
        await store.send(.saveTapped(plan.id))
    }

    @Test
    func askToFixSendsFailureBackToModel() async {
        let plan = AgentFixtures.plan(statuses: [.failed, .skipped])
        var failedPlan = plan
        failedPlan.steps[0].error = "denied"
        let model = ScriptedModel([#"{"type":"message","text":"fixed"}"#])
        let store = TestStore(initialState: .fixture(messages: [AgentFixtures.planMessage(failedPlan)])) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.stream = { model.stream($0) }
            $0.agentConversationClient.systemInfo = { .fixture }
        }
        store.exhaustivity = .off

        await store.send(.askToFix(plan.id)) {
            $0.isGenerating = true
        }
        await store.receive(\.replyFinished)
        #expect(model.prompts.value.first?.contains("Step 1 failed: denied") == true)
        #expect(store.state.messages.count == 3)
    }

    @Test
    func stopRunMarksRunningStepFailedAndSkipsRest() async {
        let plan = AgentFixtures.plan(statuses: [.running, .pending])
        var state = AgentConversationReducer.State.fixture(messages: [AgentFixtures.planMessage(plan)])
        state.runningPlanID = plan.id
        let store = TestStore(initialState: state) {
            AgentConversationReducer()
        }
        await store.send(.stopRun) {
            $0.runningPlanID = nil
            $0.updatePlan(plan.id) {
                $0.steps[0].status = .stopped
                $0.steps[1].status = .skipped
            }
        }
    }
}
