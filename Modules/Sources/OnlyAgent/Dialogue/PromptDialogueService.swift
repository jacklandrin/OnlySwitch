//
//  PromptDialogueService.swift
//  Modules
//
//  Created by Bo Liu on 17.11.25.
//

import Dependencies
import DependenciesMacros
import Extensions
import Foundation

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
    
    public var generatePlan: @Sendable (
        _ prompt: String,
        _ context: TaskContext,
        _ modelProvider: ModelProvider,
        _ model: String
    ) async throws -> [ExecutionStep] = { _,_,_,_ in [] }
    
    public var generateNextStep: @Sendable (
        _ history: [StepResult],
        _ remainingGoal: String,
        _ context: TaskContext,
        _ modelProvider: ModelProvider,
        _ model: String
    ) async throws -> ExecutionStep = { _,_,_,_,_ in
        throw NSError(domain: "PromptDialogueService", code: -1)
    }
    
    public var executeStep: @Sendable (ExecutionStep) async throws -> StepResult = { _ in
        throw NSError(domain: "PromptDialogueService", code: -1)
    }
    
    public var generateFix: @Sendable (
        _ failedStep: ExecutionStep,
        _ error: String,
        _ context: TaskContext,
        _ modelProvider: ModelProvider,
        _ model: String
    ) async throws -> ExecutionStep = { _,_,_,_,_ in
        throw NSError(domain: "PromptDialogueService", code: -1)
    }
        
}

@available(macOS 26.0, *)
extension PromptDialogueService: DependencyKey {
    public static let liveValue: Self = {
        let generater = AgentCommandGenerater()
        let planner = TaskPlanner()
        let executor = StepExecutor.shared
        
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
        } generatePlan: { prompt, context, modelProvider, model in
            try await planner.generateInitialPlan(
                prompt: prompt,
                context: context,
                modelProvider: modelProvider,
                model: model
            )
        } generateNextStep: { history, remainingGoal, context, modelProvider, model in
            try await planner.generateNextStep(
                history: history,
                remainingGoal: remainingGoal,
                context: context,
                modelProvider: modelProvider,
                model: model
            )
        } executeStep: { step in
            try await executor.executeStep(step)
        } generateFix: { failedStep, error, context, modelProvider, model in
            try await planner.generateFixForStep(
                failedStep: failedStep,
                error: error,
                context: context,
                modelProvider: modelProvider,
                model: model
            )
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
