//
//  AgentCommand.swift
//  Modules
//
//  Created by Bo Liu on 15.11.25.
//

import Extensions
import Foundation
import OSLog

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
                let queryMessage = """
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
    
    private func call(queryMessage: String, modelProvider: ModelProvider, model: String) async throws -> String {
        let script = switch modelProvider {
            case .ollama: try await OllamaTool().call(arguments: .init(prompt: queryMessage, model: model))
            case .openai: try await OpenAITool().call(arguments: .init(prompt: queryMessage, model: model))
            case .gemini: try await GeminiTool().call(arguments: .init(prompt: queryMessage, model: model))
        }
        return script
    }
}
