//
//  OpenAITool.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import OSLog
import FoundationModels
import Foundation
import Dependencies

@available(macOS 26.0, *)
final class OpenAITool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "The prompt about apple script generation to request external Open AI models")
        let prompt: String
        let model: String
    }
    
    let description = "Request external Open AI models by a prompt"
    let name = "OpenAIModels"
    
    func call(arguments: Arguments) async throws -> String {
        @Dependency(\.openAIService) var openAIService
        Logger.onlyAgentDebug.log("[Open AI] model:\(arguments.model) prompt:\(arguments.prompt)")

        let message = try await openAIService.chat(arguments.model, arguments.prompt)
        Logger.onlyAgentDebug.log("[Open AI] \(message)")
        return message
    }
}
