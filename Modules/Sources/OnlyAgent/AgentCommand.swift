//
//  AgentCommand.swift
//  Modules
//
//  Created by Bo Liu on 15.11.25.
//

import Extensions
import FoundationModels
import Foundation
//import Playgrounds

@available(macOS 26.0, *)
@Generable
public struct AgentCommand: Equatable {
    let id: String = UUID().uuidString
    @Guide(description: "an apple script command that can be executed in macOS for a specific purpose")
    let command: String
}

@available(macOS 26.0, *)
final public class AgentCommandGenerater {
    private var session: LanguageModelSession
    
    public var modelProvider: String
    
    public init(modelProvider: String) throws {
        self.modelProvider = modelProvider
        let model = SystemLanguageModel.default
        
        switch model.availability {
        case .available:
            self.session = LanguageModelSession(
                tools: [OllamaTool()],
                instructions: "You are a helpful assistant. You can generate an executable apple script command in macOS for a specific purpose."
            )
        case .unavailable(let reason):
            throw NSError(domain: "jacklandrin.onlyswitch.ai", code: 0, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }
    
    public func execute(description: String, model: String) async throws {
        let response = try await session.respond(generating: AgentCommand.self) {
            """
            1. Prompt for tool input:
            Generate an apple script command for this purpose: \(description),
            It can support macOS 26.0 and above.
            Just simply give me the doable apple script without explanation.
            Above are all part of prompt for tool input.
            2. Please use \(model) as model for tool input
            3. Extract the executable apple script from the tool output. Keep the break lines if it has.
            """
        }

        let scriptCommand = response.content
        print("command: \(scriptCommand)")
        _ = try await scriptCommand.command.runAppleScript()
    }
}

//#Playground {
//    if #available(macOS 26.0, *) {
//        let generater = try AgentCommandGenerater(modelProvider: "Ollama")
//        try? await generater.execute(description: "Switch to dark mode", model: "gpt-oss:120b")
//    }
//}
