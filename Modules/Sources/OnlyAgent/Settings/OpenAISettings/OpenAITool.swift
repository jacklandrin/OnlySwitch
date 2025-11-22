//
//  OpenAITool.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import OSLog
import Foundation
import Dependencies

final class OpenAITool {
    func call(arguments: ToolArguments) async throws -> String {
        @Dependency(\.openAIService) var openAIService
        Logger.onlyAgentDebug.log("[Open AI] model: \(arguments.model)\n prompt: \(arguments.prompt)")

        let message = try await openAIService.chat(arguments.model, arguments.prompt)
        Logger.onlyAgentDebug.log("[Open AI] \(message)")
        return message
    }
}
