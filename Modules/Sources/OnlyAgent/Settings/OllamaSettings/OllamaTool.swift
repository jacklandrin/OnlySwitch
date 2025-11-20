//
//  OllamaTool.swift
//  Modules
//
//  Created by Bo Liu on 16.11.25.
//

import OSLog
import FoundationModels
import Foundation
import Dependencies

@available(macOS 26.0, *)
final class OllamaTool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "The prompt about apple script generation to request external Ollama AI models")
        let prompt: String
        let model: String
    }
    
    let description = "Request external Ollama AI models by a prompt"
    let name = "OllamaModels"
    
    func call(arguments: Arguments) async throws -> String {
        @Dependency(\.ollamaRequestService) var ollamaRequestService
        Logger.onlyAgentDebug.log("[Ollama] model:\(arguments.model) prompt:\(arguments.prompt)")

        let message = try await ollamaRequestService.chat(arguments.model, arguments.prompt)
        Logger.onlyAgentDebug.log("[Ollama] \(message)")
        return message
    }
}

