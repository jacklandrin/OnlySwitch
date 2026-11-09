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
import OSLog

@available(macOS 26.0, *)
@DependencyClient
public struct PromptDialogueService: Sendable {
    public var request: @Sendable (
        _ prompt: AgentPrompt,
        _ modelProvider: ModelProvider,
        _ model: String,
        _ isAgentMode: Bool
    ) async throws -> String = { _,_,_,_ in "" }
    
    public var requestStream: @Sendable (
        _ prompt: AgentPrompt,
        _ modelProvider: ModelProvider,
        _ model: String,
        _ isAgentMode: Bool
    ) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> = { _, _, _, _ in
        AsyncThrowingStream { continuation in
            continuation.yield(.completed(finalText: ""))
            continuation.finish()
        }
    }
    
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
        return .init { prompt, modelProvider, model, isAgentMode in
            let generator = AgentCommandGenerater()
            do {
                let script = try await generator.execute(
                    prompt: prompt,
                    modelProvider: modelProvider,
                    model: model,
                    isAgentModel: isAgentMode
                )
                return script
            } catch {
                Logger.onlyAgentDebug.error("\(error)")
                throw error
            }
        } requestStream: { prompt, modelProvider, model, isAgentMode in
            let generator = AgentCommandGenerater()
            return try await generator.executeStream(
                prompt: prompt,
                modelProvider: modelProvider,
                model: model,
                isAgentModel: isAgentMode
            )
        } execute: { script in
            _ = try await script.runAppleScript()
        } generatePlan: { prompt, context, modelProvider, model in
            let planner = TaskPlanner()
            return try await planner.generateInitialPlan(
                prompt: prompt,
                context: context,
                modelProvider: modelProvider,
                model: model
            )
        } generateNextStep: { history, remainingGoal, context, modelProvider, model in
            let planner = TaskPlanner()
            return try await planner.generateNextStep(
                history: history,
                remainingGoal: remainingGoal,
                context: context,
                modelProvider: modelProvider,
                model: model
            )
        } executeStep: { step in
            return try await StepExecutor.shared.executeStep(step)
        } generateFix: { failedStep, error, context, modelProvider, model in
            let planner = TaskPlanner()
            return try await planner.generateFixForStep(
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
