//
//  TaskPlanner.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import OSLog
import Foundation
import Extensions

@available(macOS 26.0, *)
public final class TaskPlanner {
    private let agentCommandGenerator = AgentCommandGenerater()
    
    public init() {}
    
    public func generateInitialPlan(
        prompt: String,
        context: TaskContext,
        modelProvider: ModelProvider,
        model: String
    ) async throws -> [ExecutionStep] {
        let systemCapabilities = context.systemCapabilities.joined(separator: ", ")
        let constraints = context.constraints.isEmpty ? "None" : context.constraints.joined(separator: ", ")
        
        let contextString = """
        Goal: "\(context.goal)"
        Constraints: \(constraints)
        System Capabilities: \(systemCapabilities)
        """
        
        Logger.onlyAgentDebug.log("[contextString] \(contextString)")
        
        let planningPrompt = agentCommandGenerator.generatePlanningPrompt(
            prompt: prompt,
            context: contextString,
            isInitialPlan: true
        )
        
        Logger.onlyAgentDebug.log("[planningPrompt] \(planningPrompt)")
        
        let response = try await agentCommandGenerator.call(
            queryMessage: planningPrompt,
            modelProvider: modelProvider,
            model: model
        )
        
        return try parsePlanFromResponse(response)
    }
    
    public func generateNextStep(
        history: [StepResult],
        remainingGoal: String,
        context: TaskContext,
        modelProvider: ModelProvider,
        model: String
    ) async throws -> ExecutionStep {
        let historySummary = history.map { result in
            "Step \(result.stepId.uuidString.prefix(8)): \(result.success ? "Success" : "Failed") - \(result.error ?? result.output ?? "No output")"
        }.joined(separator: "\n")
        
        let systemState = context.currentSystemState?.runningApplications.joined(separator: ", ") ?? "Unknown"
        
        let contextString = """
        Original Goal: "\(context.goal)"
        Remaining Goal: "\(remainingGoal)"
        Execution History:
        \(historySummary)
        
        Current System State:
        Running Applications: \(systemState)
        """
        
        let nextStepPrompt = agentCommandGenerator.generatePlanningPrompt(
            prompt: remainingGoal,
            context: contextString,
            isInitialPlan: false
        )
        
        let response = try await agentCommandGenerator.call(
            queryMessage: nextStepPrompt,
            modelProvider: modelProvider,
            model: model
        )
        
        return try parseStepFromResponse(response, stepNumber: history.count + 1)
    }
    
    public func generateFixForStep(
        failedStep: ExecutionStep,
        error: String,
        context: TaskContext,
        modelProvider: ModelProvider,
        model: String
    ) async throws -> ExecutionStep {
        let failedStepString = """
        Description: \(failedStep.description)
        AppleScript: \(failedStep.appleScript)
        Expected Outcome: \(failedStep.expectedOutcome ?? "N/A")
        """
        
        let fixPrompt = agentCommandGenerator.generateFixPrompt(
            failedStep: failedStepString,
            error: error
        )
        
        let response = try await agentCommandGenerator.call(
            queryMessage: fixPrompt,
            modelProvider: modelProvider,
            model: model
        )
        
        return try parseStepFromResponse(response, stepNumber: failedStep.stepNumber)
    }
    
    private func parsePlanFromResponse(_ response: String) throws -> [ExecutionStep] {
        // Clean the response - remove markdown code blocks if present
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedResponse.hasPrefix("```") {
            let lines = cleanedResponse.components(separatedBy: .newlines)
            cleanedResponse = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw TaskPlannerError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let stepData = try decoder.decode([StepData].self, from: data)
        
        return stepData.enumerated().map { index, data in
            ExecutionStep(
                stepNumber: data.stepNumber ?? (index + 1),
                description: data.description,
                appleScript: data.appleScript,
                expectedOutcome: data.expectedOutcome
            )
        }
    }
    
    private func parseStepFromResponse(_ response: String, stepNumber: Int) throws -> ExecutionStep {
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedResponse.hasPrefix("```") {
            let lines = cleanedResponse.components(separatedBy: .newlines)
            cleanedResponse = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        
        guard let data = cleanedResponse.data(using: .utf8) else {
            throw TaskPlannerError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let stepData = try decoder.decode(StepData.self, from: data)
        
        return ExecutionStep(
            stepNumber: stepData.stepNumber ?? stepNumber,
            description: stepData.description,
            appleScript: stepData.appleScript,
            expectedOutcome: stepData.expectedOutcome
        )
    }
}

private struct StepData: Codable {
    let stepNumber: Int?
    let description: String
    let appleScript: String
    let expectedOutcome: String?
}

enum TaskPlannerError: Error {
    case invalidResponse
    case parsingFailed
}


