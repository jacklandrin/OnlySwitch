//
//  AgentCommand.swift
//  Modules
//
//  Created by Bo Liu on 15.11.25.
//

import Extensions
import FoundationModels
import Foundation
import OSLog
//import Playgrounds

public enum ModelProvider: String {
    case ollama
    case openai
}

@available(macOS 26.0, *)
@Generable
public struct AgentCommand: Equatable {
    let id: String = UUID().uuidString
    @Guide(description: "a formatted apple script command that can be executed in macOS for a specific purpose line by line.")
    let appleScript: [String]
}

@available(macOS 26.0, *)
final public class AgentCommandGenerater {
    
    public init() throws {
        let model = SystemLanguageModel.default
        
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw NSError(domain: "jacklandrin.onlyswitch.ai", code: 0, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }
    
    public func execute(
        description: String,
        modelProvider: ModelProvider = .ollama,
        model: String,
        isAgentModel: Bool = false
    ) async throws -> String {
        let tools: [any Tool] = switch modelProvider {
                case .ollama: [OllamaTool()]
                case .openai: [OpenAITool()]
        }
        
        let queryMessage = """
                        Write an AppleScript for the purpose: \(description).
                        Ensure compatibility with the latest macOS.
                        Output strict rules:
                        - Return ONLY the raw code.
                        - No markdown formatting.
                        - No explanations.
                        - Keep proper indentation.
            """
        
        let script = switch modelProvider {
            case .ollama: try await generateWithAppleIntelligence(queryMessage: queryMessage, model: model, tools: tools)
            case .openai: try await OpenAITool().call(arguments: .init(prompt: queryMessage, model: model))
        }
        
        Logger.onlyAgentDebug.log("extracted command: \n\(script)")
        if isAgentModel {
            _ = try await script.runAppleScript()
        }
        
        return script
    }
    
    private func generateWithAppleIntelligence(queryMessage: String, model: String, tools: [any Tool]) async throws -> String {
        let session = LanguageModelSession(
            tools: tools,
            instructions: "You are a helpful assistant. You can generate an executable apple script command in macOS for a specific purpose."
        )
        let response = try await session.respond(generating: AgentCommand.self) {
            """
            1. Prompt for tool input:
            \(queryMessage)
            Above are all part of prompt for tool input.
            2. Please use \(model) as model for tool input
            3. Extract the formatted and executive apple script line by line from the tool output. 
            """
        }

        let scriptCommand = response.content
        let separator = scriptCommand.appleScript.first?.contains("do shell script") == true ? " " : "\n"
        let script = scriptCommand.appleScript.joined(separator: separator)
        return script
    }
}

//#Playground {
//    if #available(macOS 26.0, *) {
//        let generater = try AgentCommandGenerater(modelProvider: "Ollama")
//        try? await generater.execute(description: "Switch to dark mode", model: "gpt-oss:120b")
//    }
//}
