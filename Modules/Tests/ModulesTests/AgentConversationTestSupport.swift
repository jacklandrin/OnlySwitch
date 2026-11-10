import ComposableArchitecture
import Foundation
@testable import OnlyAgent

extension AgentConversationReducer.State {
    static func fixture(
        model: CurrentAIModel? = CurrentAIModel(provider: "openai", model: "gpt-test"),
        mode: AgentExecutionMode = .preview,
        messages: IdentifiedArrayOf<AgentMessage> = []
    ) -> Self {
        var state = Self(
            currentAIModel: Shared(value: model),
            executionMode: Shared(value: mode)
        )
        state.messages = messages
        return state
    }
}

/// Streams queued replies in order and records every prompt it receives.
final class ScriptedModel: Sendable {
    let prompts = LockIsolated<[String]>([])
    let requests = LockIsolated<[ModelGenerationRequest]>([])
    let replies: LockIsolated<[String]>

    init(_ replies: [String]) {
        self.replies = LockIsolated(replies)
    }

    func stream(_ request: ModelGenerationRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        requests.withValue { $0.append(request) }
        prompts.withValue { $0.append(request.prompt) }
        let reply = replies.withValue { $0.isEmpty ? "" : $0.removeFirst() }
        return AsyncThrowingStream { continuation in
            continuation.yield(.thinkingDelta("thinking"))
            continuation.yield(.completed(finalText: reply))
            continuation.finish()
        }
    }
}

extension AgentSystemInfo {
    static let fixture = AgentSystemInfo(
        osVersion: "26.1.0",
        osBuild: "26B82",
        architecture: "arm64",
        modelIdentifier: "Mac16,1",
        memoryGB: 16,
        language: "zh-Hans",
        region: "DE",
        displayCount: 2,
        isDarkMode: true
    )
}

enum AgentFixtures {
    static let questionsJSON = #"{"type":"questions","questions":[{"question":"Which display?","options":["Built-in","External"]}]}"#
    static let twoStepPlanJSON = #"{"type":"plan","title":"Dark and loud","summary":"","steps":[{"title":"Dark","kind":"applescript","code":"tell dark"},{"title":"Loud","kind":"shell","code":"echo loud"}]}"#

    static func plan(
        id: UUID = UUID(10),
        statuses: [AgentStepStatus] = [.pending, .pending]
    ) -> AgentPlan {
        let steps = [
            AgentScriptStep(id: UUID(11), title: "Dark", kind: .applescript, code: "tell dark", status: statuses[0]),
            AgentScriptStep(id: UUID(12), title: "Loud", kind: .shell, code: "echo loud", status: statuses[1]),
        ]
        return AgentPlan(id: id, title: "Dark and loud", summary: "", steps: steps)
    }

    static func planMessage(_ plan: AgentPlan, id: UUID = UUID(20)) -> AgentMessage {
        AgentMessage(id: id, role: .assistant, content: .plan(plan))
    }
}

struct TestFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Adapts a simple async closure to the streaming `run` dependency.
func agentRun(
    _ body: @escaping @Sendable (AgentScriptKind, String) async throws -> String
) -> @Sendable (AgentScriptKind, String) -> AsyncThrowingStream<AgentRunEvent, Error> {
    { kind, code in
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.finished(try await body(kind, code)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
