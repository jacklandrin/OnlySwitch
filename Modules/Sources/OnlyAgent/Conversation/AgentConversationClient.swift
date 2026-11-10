//
//  AgentConversationClient.swift
//  Modules
//

import Dependencies
import DependenciesMacros
import Extensions
import Foundation
import OSLog
import Sharing

/// Effects used by Only Agent: model listing and streaming, and script execution.
///
/// Script execution is a security-sensitive effect and is only reachable
/// through `run`, so reducers and tests control exactly when a script runs.
@DependencyClient
public struct AgentConversationClient: Sendable {
    public var availableModels: @Sendable () async -> [ModelProvider: [String]] = { [:] }
    public var stream: @Sendable (ModelGenerationRequest) async throws -> AsyncThrowingStream<ModelStreamEvent, Error>
    /// Runs one step. Emits `.passwordRequested` when sudo needs a password
    /// (answer it with `answerPassword`) and `.finished` with the output.
    public var run: @Sendable (_ kind: AgentScriptKind, _ code: String) -> AsyncThrowingStream<AgentRunEvent, Error> = { _, _ in
        AsyncThrowingStream { $0.finish(throwing: CancellationError()) }
    }
    /// Delivers the user's password for a request; `nil` cancels the step.
    /// The password is passed straight to the running step and never stored.
    public var answerPassword: @Sendable (_ requestID: UUID, _ password: String?) async -> Void
    /// Collected on every turn so the model writes scripts for this Mac.
    public var systemInfo: @Sendable () async -> AgentSystemInfo = { AgentSystemInfo() }
}

extension AgentConversationClient: DependencyKey {
    public static var liveValue: Self {
        @Dependency(\.modelProviderService) var modelProviderService
        let providerService = modelProviderService
        let passwordBroker = AgentPasswordBroker()
        return Self(
            availableModels: {
                var tags: [ModelProvider: [String]] = [:]
                if #available(macOS 26.0, *) {
                    @Shared(.ollamaModels) var ollamaModels: [OllamaTag]
                    tags[.ollama] = ollamaModels.map(\.model)
                }
                for provider in [ModelProvider.openai, .codex, .gemini] {
                    do {
                        tags[provider] = try await providerService.models(provider).map(\.model)
                    } catch {
                        Logger.onlyAgentDebug.warning("Loading \(provider.rawValue, privacy: .public) models failed: \(error)")
                    }
                }
                return tags
            },
            stream: { request in
                try await providerService.instructedChatStream(request)
            },
            run: { kind, code in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            let output = try await AgentScriptRunner.run(kind: kind, code: code) { prompt in
                                await passwordBroker.request(prompt: prompt) { request in
                                    continuation.yield(.passwordRequested(request))
                                }
                            }
                            continuation.yield(.finished(output))
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            answerPassword: { requestID, password in
                await passwordBroker.answer(requestID, password: password)
            },
            systemInfo: {
                AgentSystemInfo.current()
            }
        )
    }

    public static let testValue = Self()
}

extension DependencyValues {
    public var agentConversationClient: AgentConversationClient {
        get { self[AgentConversationClient.self] }
        set { self[AgentConversationClient.self] = newValue }
    }
}
