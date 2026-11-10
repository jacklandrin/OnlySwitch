//
//  EvolutionScriptGenerationClient.swift
//  Modules
//

import Dependencies
import DependenciesMacros
import Foundation
import OSLog
import Sharing

/// Writes Evolution scripts from a description with the model chosen in
/// Only Agent. It never runs a script and never changes the model choice.
@DependencyClient
public struct EvolutionScriptGenerationClient: Sendable {
    public var isModelSelected: @Sendable () -> Bool = { false }
    public var generate: @Sendable (
        _ description: String,
        _ target: EvolutionScriptTarget
    ) async throws -> GeneratedEvolutionScripts
}

extension EvolutionScriptGenerationClient: DependencyKey {
    public static var liveValue: Self {
        @Dependency(\.modelProviderService) var modelProviderService
        let service = modelProviderService
        return Self(
            isModelSelected: {
                @Shared(.currentAIModel) var current
                return current?.modelProvider != nil
            },
            generate: { description, target in
                @Shared(.currentAIModel) var current
                guard let current, let provider = current.modelProvider else {
                    throw EvolutionScriptGenerationError.noModelSelected
                }
                let request = ModelGenerationRequest(
                    provider: provider,
                    model: current.model,
                    purpose: .agent,
                    systemInstructions: EvolutionScriptPromptBuilder.systemInstructions(
                        target: target,
                        systemInfo: AgentSystemInfo.current()
                    ),
                    prompt: EvolutionScriptPromptBuilder.prompt(description: description),
                    maximumOutputTokens: 4096
                )
                var accumulated = ""
                var finalText: String?
                for try await event in try await service.instructedChatStream(request) {
                    switch event {
                    case let .contentDelta(delta):
                        accumulated += delta
                    case .thinkingDelta:
                        break
                    case let .completed(text):
                        finalText = text.isEmpty ? accumulated : text
                    }
                }
                do {
                    return try EvolutionScriptReplyParser.parse(finalText ?? accumulated, target: target)
                } catch let error as EvolutionScriptGenerationError {
                    // Only the category is logged: the reply may echo the user's request.
                    Logger.onlyAgentDebug.warning("Evolution script reply rejected: \(error.category, privacy: .public)")
                    throw error
                }
            }
        )
    }

    public static let testValue = Self()
}

extension DependencyValues {
    public var evolutionScriptGenerationClient: EvolutionScriptGenerationClient {
        get { self[EvolutionScriptGenerationClient.self] }
        set { self[EvolutionScriptGenerationClient.self] = newValue }
    }
}
