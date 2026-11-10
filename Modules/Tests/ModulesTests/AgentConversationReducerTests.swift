import ComposableArchitecture
import Foundation
import Testing
@testable import OnlyAgent

@MainActor
struct AgentConversationReducerTests {
    @Test
    func sendingPromptAppendsQuestions() async {
        let model = ScriptedModel([AgentFixtures.questionsJSON])
        let store = TestStore(initialState: .fixture()) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.stream = { model.stream($0) }
            $0.agentConversationClient.systemInfo = { .fixture }
        }

        await store.send(.binding(.set(\.draft, "Dim my screen"))) {
            $0.draft = "Dim my screen"
        }
        await store.send(.sendTapped) {
            $0.draft = ""
            $0.messages = [AgentMessage(id: UUID(0), role: .user, content: .text("Dim my screen"))]
            $0.isGenerating = true
        }
        await store.receive(\.streamEvent) {
            $0.thinkingText = "thinking"
        }
        await store.receive(\.replyFinished) {
            $0.isGenerating = false
            $0.thinkingText = ""
            let question = AgentQuestion(id: UUID(1), prompt: "Which display?", options: ["Built-in", "External"])
            $0.messages.append(AgentMessage(id: UUID(2), role: .assistant, content: .questions([question], answered: false)))
        }
        #expect(model.prompts.value.count == 1)
        #expect(model.prompts.value[0].contains("User: Dim my screen"))
        let request = model.requests.value[0]
        #expect(request.systemInstructions.contains("macOS 26.1.0 (build 26B82)"))
        #expect(request.purpose == .agent)
        #expect(request.provider == .openai)
        #expect(request.model == "gpt-test")
        #expect(request.conversationID == store.state.conversationID)
    }

    @Test
    func systemInfoIsCollectedFreshForEveryTurn() async {
        let model = ScriptedModel([#"{"type":"message","text":"a"}"#, #"{"type":"message","text":"b"}"#])
        let calls = LockIsolated(0)
        let store = TestStore(initialState: .fixture()) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.stream = { model.stream($0) }
            $0.agentConversationClient.systemInfo = {
                calls.withValue { $0 += 1 }
                var info = AgentSystemInfo.fixture
                info.isDarkMode = calls.value == 1
                return info
            }
        }
        store.exhaustivity = .off

        await store.send(.binding(.set(\.draft, "Toggle dark mode")))
        await store.send(.sendTapped)
        await store.receive(\.replyFinished)
        await store.send(.binding(.set(\.draft, "Again")))
        await store.send(.sendTapped)
        await store.receive(\.replyFinished)

        #expect(calls.value == 2)
        #expect(model.requests.value[0].systemInstructions.contains("Appearance: Dark"))
        #expect(model.requests.value[1].systemInstructions.contains("Appearance: Light"))
    }

    @Test
    func answeringQuestionsStartsNextTurnWithAnswers() async {
        let question = AgentQuestion(id: UUID(101), prompt: "Which display?", options: ["Built-in", "External"])
        let model = ScriptedModel(["""
        {"type":"message","text":"ok"}
        """])
        let store = TestStore(initialState: .fixture(messages: [
            AgentMessage(id: UUID(100), role: .user, content: .text("Dim")),
            AgentMessage(id: UUID(102), role: .assistant, content: .questions([question], answered: false)),
        ])) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.stream = { model.stream($0) }
            $0.agentConversationClient.systemInfo = { .fixture }
        }
        store.exhaustivity = .off

        await store.send(.submitAnswers(messageID: UUID(102)))
        #expect(model.prompts.value.isEmpty)
        #expect(store.state.isGenerating == false)

        await store.send(.answerChanged(messageID: UUID(102), questionID: UUID(101), answer: "Built-in"))
        await store.send(.submitAnswers(messageID: UUID(102)))
        await store.receive(\.replyFinished)

        #expect(model.prompts.value.count == 1)
        #expect(model.prompts.value[0].contains("Which display?: Built-in"))
        guard case let .questions(_, answered) = store.state.messages[id: UUID(102)]?.content else {
            Issue.record("Expected questions")
            return
        }
        #expect(answered)
        #expect(store.state.messages.last?.content == .text("ok"))
    }

    @Test
    func planInPreviewModeDoesNotRun() async {
        let model = ScriptedModel([AgentFixtures.twoStepPlanJSON])
        let store = TestStore(initialState: .fixture(mode: .preview)) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.stream = { model.stream($0) }
            $0.agentConversationClient.systemInfo = { .fixture }
            // `run` is left unimplemented: calling it fails the test.
        }
        store.exhaustivity = .off

        await store.send(.binding(.set(\.draft, "Dark mode and volume up")))
        await store.send(.sendTapped)
        await store.receive(\.replyFinished)
        await store.finish()

        guard case let .plan(plan) = store.state.messages.last?.content else {
            Issue.record("Expected a plan")
            return
        }
        #expect(plan.steps.map(\.status) == [.pending, .pending])
        #expect(store.state.runningPlanID == nil)
    }

    @Test
    func planInDirectModeRunsImmediately() async {
        let model = ScriptedModel([AgentFixtures.twoStepPlanJSON])
        let ran = LockIsolated<[String]>([])
        let store = TestStore(initialState: .fixture(mode: .direct)) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.stream = { model.stream($0) }
            $0.agentConversationClient.systemInfo = { .fixture }
            $0.agentConversationClient.run = agentRun { _, code in
                ran.withValue { $0.append(code) }
                return ""
            }
        }
        store.exhaustivity = .off

        await store.send(.binding(.set(\.draft, "Dark mode and volume up")))
        await store.send(.sendTapped)
        await store.receive(\.replyFinished)
        await store.receive(\.runPlan)
        await store.finish()

        #expect(ran.value == ["tell dark", "echo loud"])
    }

    @Test
    func streamFailureAppendsError() async {
        let store = TestStore(initialState: .fixture()) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.stream = { _ in throw TestFailure(message: "offline") }
            $0.agentConversationClient.systemInfo = { .fixture }
        }

        await store.send(.binding(.set(\.draft, "Hi"))) {
            $0.draft = "Hi"
        }
        await store.send(.sendTapped) {
            $0.draft = ""
            $0.messages = [AgentMessage(id: UUID(0), role: .user, content: .text("Hi"))]
            $0.isGenerating = true
        }
        await store.receive(\.replyFailed) {
            $0.isGenerating = false
            $0.messages.append(AgentMessage(id: UUID(1), role: .assistant, content: .error("offline")))
        }
    }

    @Test
    func emptyDraftIsIgnored() async {
        let store = TestStore(initialState: .fixture()) {
            AgentConversationReducer()
        }
        await store.send(.binding(.set(\.draft, "   "))) {
            $0.draft = "   "
        }
        await store.send(.sendTapped)
    }

    @Test
    func newConversationClearsTranscript() async {
        let store = TestStore(initialState: .fixture(messages: [
            AgentMessage(id: UUID(0), role: .user, content: .text("Hi")),
        ])) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.agentConversationClient.systemInfo = { AgentSystemInfo() }
        }
        await store.send(.newConversation) {
            $0.messages = []
            $0.conversationID = UUID(0)
        }
        await store.receive(\.systemInfoLoaded) {
            $0.suggestions = AgentSuggestion.make(for: AgentSystemInfo())
        }
    }
}
