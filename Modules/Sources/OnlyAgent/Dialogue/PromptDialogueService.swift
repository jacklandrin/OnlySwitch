//
//  PromptDialogueService.swift
//  Modules
//
//  Created by Bo Liu on 17.11.25.
//

import Dependencies
import DependenciesMacros
import Extensions

@available(macOS 26.0, *)
@DependencyClient
public struct PromptDialogueService: Sendable {
    public var request: @Sendable (
        _ prompt: AgentPrompt,
        _ modelProvider: ModelProvider,
        _ model: String,
        _ isAgentMode: Bool
    ) async throws -> String = { _,_,_,_ in "" }
    
    public var execute: @Sendable (String) async throws -> Void
        
}

@available(macOS 26.0, *)
extension PromptDialogueService: DependencyKey {
    public static let liveValue: Self = {
        let generater = AgentCommandGenerater()
        return .init { prompt, modelProvider, model, isAgentMode in
            let script = try await generater.execute(
                prompt: prompt,
                modelProvider: modelProvider,
                model: model,
                isAgentModel: isAgentMode
            )
            return script
        } execute: { script in
            _ = try await script.runAppleScript()
        }
    }()
    
    public static let testValue = Self()
}

@available(macOS 26.0, *)
extension DependencyValues {
    public var promptDialogueService: PromptDialogueService {
        get { self[PromptDialogueService.self] }
        set { self[PromptDialogueService.self] = newValue }
    }
}
