//
//  OllamaTool.swift
//  Modules
//
//  Created by Bo Liu on 16.11.25.
//

import OSLog
import Foundation
import Dependencies

@available(macOS 26.0, *)
final class OllamaTool {
    func call(arguments: ToolArguments) async throws -> String {
        @Dependency(\.ollamaRequestService) var ollamaRequestService
        Logger.onlyAgentDebug.log("[Ollama] model:\(arguments.model) prompt:\(arguments.prompt)")

        let message = try await ollamaRequestService.chat(arguments.model, arguments.prompt)
        Logger.onlyAgentDebug.log("[Ollama] \(message)")
        return message
    }
}

