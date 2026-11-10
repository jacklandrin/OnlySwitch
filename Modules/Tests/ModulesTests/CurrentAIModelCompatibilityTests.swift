import ComposableArchitecture
import Foundation
import Testing
@testable import OnlyAgent

/// Guards the stored model selection so upgrading users keep their choice.
@MainActor
struct CurrentAIModelCompatibilityTests {
    @Test(arguments: [
        (#"{"provider":"openai","model":"gpt-4o"}"#, "openai", "gpt-4o"),
        (#"{"provider":"claude","model":"claude-opus-5-5"}"#, "claude", "claude-opus-5-5"),
        (#"{"model":"llama3","provider":"ollama"}"#, "ollama", "llama3"),
    ])
    func legacyJSONDecodes(json: String, provider: String, model: String) throws {
        let decoded = try JSONDecoder().decode(CurrentAIModel.self, from: Data(json.utf8))
        #expect(decoded == CurrentAIModel(provider: provider, model: model))
    }

    @Test
    func encodingKeepsLegacyKeys() throws {
        let data = try JSONEncoder().encode(CurrentAIModel(provider: "gemini", model: "g"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["provider": "gemini", "model": "g"])
    }

    @Test
    func storagePathIsUnchanged() {
        #expect(
            CurrentAIModel.storageURL(bundleName: "OnlySwitch")
                == URL.applicationSupportDirectory.appending(component: "OnlySwitch/currentAIModel")
        )
    }

    @Test
    func providerRawValuesAreUnchanged() {
        #expect(ModelProvider.allCases.map(\.rawValue) == ["ollama", "openai", "codex", "gemini", "claude"])
    }

    @Test
    func loadingModelsNeverChangesStoredSelection() async {
        let stored = CurrentAIModel(provider: "ollama", model: "offline-model")
        let store = TestStore(initialState: .fixture(model: stored)) {
            AgentConversationReducer()
        } withDependencies: {
            $0.agentConversationClient.availableModels = { [.openai: ["gpt-a"]] }
            $0.agentConversationClient.systemInfo = { AgentSystemInfo() }
        }

        await store.send(.appear)
        await store.receive(\.systemInfoLoaded) {
            $0.suggestions = AgentSuggestion.make(for: AgentSystemInfo())
        }
        await store.receive(\.modelsLoaded) {
            $0.modelTags = [.openai: ["gpt-a"]]
        }
        await store.send(.modelsLoaded([:])) {
            $0.modelTags = [:]
        }
        #expect(store.state.currentAIModel == stored)
    }

    @Test
    func unknownProviderIsKeptAndSendingShowsError() async {
        let stored = CurrentAIModel(provider: "legacy", model: "old")
        let store = TestStore(initialState: .fixture(model: stored)) {
            AgentConversationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            // `stream` is unimplemented: calling it fails the test.
        }

        await store.send(.binding(.set(\.draft, "Hi"))) {
            $0.draft = "Hi"
        }
        await store.send(.sendTapped) {
            $0.messages = [AgentMessage(id: UUID(0), role: .assistant, content: .notice(.selectModel))]
        }
        #expect(store.state.currentAIModel == stored)
        #expect(store.state.draft == "Hi")
    }

    @Test
    func selectingModelIsTheOnlyWrite() async {
        let store = TestStore(initialState: .fixture(model: nil)) {
            AgentConversationReducer()
        }
        await store.send(.selectAIModel(provider: .claude, model: "claude-sonnet-5-5")) {
            $0.$currentAIModel.withLock { $0 = CurrentAIModel(provider: "claude", model: "claude-sonnet-5-5") }
        }
    }
}
