//
//  PromptDialogueService.swift
//  Modules
//
//  Created by Bo Liu on 17.11.25.
//

import Dependencies
import DependenciesMacros
import Extensions

@DependencyClient
public struct PromptDialogueService: Sendable {
    public var request: @Sendable (
        _ description: String,
        _ modelProvider: ModelProvider,
        _ model: String,
        _ isAgentMode: Bool
    ) async throws -> String = { _,_,_,_ in "" }
    
    public var execute: @Sendable (String) async throws -> Void
        
}

extension PromptDialogueService: DependencyKey {
    public static let liveValue: Self = .init { description, modelProvider, model, isAgentMode in
        if #available(macOS 26.0, *) {
            let generater = try AgentCommandGenerater()
            let script = try await generater.execute(
                description: description,
                modelProvider: modelProvider,
                model: model,
                isAgentModel: isAgentMode
            )
            return script
        }
        return ""
    } execute: { script in
        _ = try await script.runAppleScript()
    }
    
    public static let testValue = Self()
}

extension DependencyValues {
    public var promptDialogueService: PromptDialogueService {
        get { self[PromptDialogueService.self] }
        set { self[PromptDialogueService.self] = newValue }
    }
}
