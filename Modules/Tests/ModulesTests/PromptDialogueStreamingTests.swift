import ComposableArchitecture
import XCTest
@testable import OnlyAgent

@available(macOS 26.0, *)
@MainActor
final class PromptDialogueStreamingTests: XCTestCase {
    func testStreamingThinkingTextAndFinalScript() async {
        var initialState = PromptDialogueReducer.State(
            prompt: "Turn on dark mode",
            isAgentMode: false
        )
        initialState.currentAIModel = CurrentAIModel(provider: ModelProvider.openai.rawValue, model: "gpt-test")
        
        let store = TestStore(initialState: initialState) {
            PromptDialogueReducer()
        } withDependencies: {
            $0.promptDialogueService.requestStream = { _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.thinkingDelta("Analyzing request..."))
                    continuation.yield(.contentDelta("tell application \"System Events\""))
                    continuation.yield(.completed(finalText: "tell application \"System Events\" to key code 144"))
                    continuation.finish()
                }
            }
            $0.promptDialogueService.request = { _, _, _, _ in "" }
        }
        
        await store.send(.sendPrompt) {
            $0.appleScript = ""
            $0.thinkingText = ""
            $0.isGenerating = true
            $0.isSuccess = nil
            $0.isMultiStepMode = false
        }
        
        await store.receive(\.receiveStreamEvent) {
            $0.thinkingText = "Analyzing request..."
        }
        
        await store.receive(\.receiveStreamEvent) {
            $0.thinkingText = "Analyzing request...tell application \"System Events\""
        }
        
        await store.receive(\.receiveStreamEvent) {
            $0.thinkingText = ""
        }
        
        await store.receive(\.generateAppleScript) {
            $0.appleScript = "tell application \"System Events\" to key code 144"
            $0.thinkingText = ""
            $0.isGenerating = false
        }
    }
    
    func testStreamingFailureClearsThinkingText() async {
        enum TestError: Error {
            case failed
        }
        
        var initialState = PromptDialogueReducer.State(
            prompt: "Turn on dark mode",
            isAgentMode: false
        )
        initialState.currentAIModel = CurrentAIModel(provider: ModelProvider.openai.rawValue, model: "gpt-test")
        initialState.thinkingText = "pending"
        
        let store = TestStore(initialState: initialState) {
            PromptDialogueReducer()
        } withDependencies: {
            $0.promptDialogueService.requestStream = { _, _, _, _ in
                throw TestError.failed
            }
            $0.promptDialogueService.request = { _, _, _, _ in "" }
        }
        
        await store.send(.sendPrompt) {
            $0.appleScript = ""
            $0.thinkingText = ""
            $0.isGenerating = true
            $0.isSuccess = nil
            $0.isMultiStepMode = false
        }
        
        await store.receive(\.generateAppleScript) {
            $0.thinkingText = ""
            $0.isGenerating = false
            $0.isSuccess = false
            $0.errorMessage = TestError.failed.localizedDescription
        }
    }

    func testAgentModeExecutesCompletedScriptWithoutAnotherModelRequest() async {
        let executedScripts = LockIsolated<[String]>([])
        let requestCount = LockIsolated(0)
        var initialState = PromptDialogueReducer.State(
            prompt: "Turn on dark mode",
            isAgentMode: true
        )
        initialState.currentAIModel = CurrentAIModel(provider: ModelProvider.openai.rawValue, model: "gpt-test")

        let store = TestStore(initialState: initialState) {
            PromptDialogueReducer()
        } withDependencies: {
            $0.promptDialogueService.execute = { script in
                executedScripts.withValue { $0.append(script) }
            }
            $0.promptDialogueService.request = { _, _, _, _ in
                requestCount.withValue { $0 += 1 }
                return ""
            }
        }

        let script = "tell application \"System Events\" to key code 144"
        await store.send(.generateAppleScript(.success(script))) {
            $0.appleScript = script
            $0.thinkingText = ""
            $0.isGenerating = false
            $0.isSuccess = true
        }

        await store.receive(\.finishExecution)

        XCTAssertEqual(executedScripts.value, [script])
        XCTAssertEqual(requestCount.value, 0)
    }
}
