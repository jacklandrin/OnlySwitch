//
//  AgentCommand.swift
//  Modules
//
//  Created by Bo Liu on 15.11.25.
//

import Extensions
import Foundation
import OSLog
import Dependencies

public enum AgentPrompt {
    case purpose(String)
    case success
    case failure
}

@available(macOS 26.0, *)
final public class AgentCommandGenerater {
    public init() {}
    
    public func execute(
        prompt: AgentPrompt,
        modelProvider: ModelProvider = .ollama,
        model: String,
        isAgentModel: Bool = false
    ) async throws -> String {
        switch prompt {
            case .purpose(let description):
                let queryMessage = purposePrompt(for: description)
                
                let script = try await call(queryMessage: queryMessage, modelProvider: modelProvider, model: model)
                
                Logger.onlyAgentDebug.log("extracted command: \n\(script)")
                if isAgentModel {
                    do {
                        _ = try await script.runAppleScript()
                    } catch {
                        _ = try await call(queryMessage: "It doesn't work, but don't need to try again.", modelProvider: modelProvider, model: model)
                        throw error
                    }
                }
                return script
            case .success:
                return try await call(queryMessage: "Good job!", modelProvider: modelProvider, model: model)
            case .failure:
                return try await call(queryMessage: "It doesn't work, but don't need to try again.", modelProvider: modelProvider, model: model)
        }
    }
    
    public func executeStream(
        prompt: AgentPrompt,
        modelProvider: ModelProvider = .ollama,
        model: String,
        isAgentModel: Bool = false
    ) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        _ = isAgentModel
        switch prompt {
        case .purpose(let description):
            return try await callStream(
                queryMessage: purposePrompt(for: description),
                modelProvider: modelProvider,
                model: model
            )
        case .success:
            let response = try await call(
                queryMessage: "Good job!",
                modelProvider: modelProvider,
                model: model
            )
            return Self.singleEventStream(.completed(finalText: response))
        case .failure:
            let response = try await call(
                queryMessage: "It doesn't work, but don't need to try again.",
                modelProvider: modelProvider,
                model: model
            )
            return Self.singleEventStream(.completed(finalText: response))
        }
    }
    
    func call(queryMessage: String, modelProvider: ModelProvider, model: String) async throws -> String {
        let script = switch modelProvider {
            case .ollama: try await OllamaTool().call(arguments: .init(prompt: queryMessage, model: model))
            case .openai: try await OpenAITool().call(arguments: .init(prompt: queryMessage, model: model))
            case .codex: try await CodexTool().call(arguments: .init(prompt: queryMessage, model: model))
            case .gemini: try await GeminiTool().call(arguments: .init(prompt: queryMessage, model: model))
            case .claude: try await ClaudeTool().call(arguments: .init(prompt: queryMessage, model: model))
        }
        return script
    }
    
    func callStream(
        queryMessage: String,
        modelProvider: ModelProvider,
        model: String
    ) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        @Dependency(\.modelProviderService) var modelProviderService
        return try await modelProviderService.chatStream(modelProvider, model, queryMessage)
    }
    
    private func purposePrompt(for description: String) -> String {
        """
        Write an AppleScript (NOT shell script, NOT bash) for: \"\(description)\".
        CRITICAL: You MUST write AppleScript code that starts with "tell application" or uses AppleScript commands.
        DO NOT write shell scripts (no #!/bin/bash, no plain shell commands).
        If you need to run shell commands, use AppleScript's "do shell script" command.
        Ensure compatibility with the latest macOS.
        Output strict rules:
        - Return ONLY raw AppleScript code.
        - No markdown formatting (no ```applescript).
        - No explanations or comments outside the code.
        - Keep proper indentation.
        - The code must be executable via osascript.
        """
    }
    
    private static func singleEventStream(_ event: ModelStreamEvent) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(event)
            continuation.finish()
        }
    }
    
    public func generatePlanningPrompt(
        prompt: String,
        context: String,
        isInitialPlan: Bool
    ) -> String {
        if isInitialPlan {
            return """
            Break down the following task into a step-by-step plan. Each step should be a single, executable AppleScript action.
            
            Task: "\(prompt)"
            Context: \(context)
            
            Create a detailed plan with multiple steps. For each step, provide:
            1. A clear description of what the step does
            2. The AppleScript code to execute it
            3. The expected outcome
            
            Format your response as a JSON array where each step has:
            - stepNumber: integer
            - description: string
            - appleScript: string (raw AppleScript code, no markdown)
            - expectedOutcome: string
            
            Return ONLY the JSON array, no markdown, no explanations.
            """
        } else {
            return """
            Based on the execution history and current system state, generate the next step to achieve the remaining goal.
            
            Context: \(context)
            
            Generate the next step as a JSON object with:
            - stepNumber: integer (next sequential number)
            - description: string
            - appleScript: string (raw AppleScript code, no markdown)
            - expectedOutcome: string
            
            Return ONLY the JSON object, no markdown, no explanations.
            """
        }
    }
    
    public func generateFixPrompt(
        failedStep: String,
        error: String
    ) -> String {
        return """
        The following step failed with an error. Generate a fixed version of the step.
        
        Original Step:
        \(failedStep)
        
        Error: \(error)
        
        Generate a corrected step as a JSON object with:
        - stepNumber: integer (same as original)
        - description: string (updated if needed)
        - appleScript: string (fixed AppleScript code, no markdown)
        - expectedOutcome: string
        
        Return ONLY the JSON object, no markdown, no explanations.
        """
    }
}
