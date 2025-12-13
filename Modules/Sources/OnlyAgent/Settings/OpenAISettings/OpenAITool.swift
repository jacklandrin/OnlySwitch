//
//  OpenAITool.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import OSLog
import Foundation
import Dependencies

@available(macOS 26.0, *)
final class OpenAITool: ModelTool {
    func call(arguments: ToolArguments) async throws -> String {
        @Dependency(\.modelProviderService) var modelProviderService
        Logger.onlyAgentDebug.log("[Open AI] model: \(arguments.model)\n prompt: \(arguments.prompt)")

        let message = try await modelProviderService.chat(.openai, arguments.model, arguments.prompt)
        Logger.onlyAgentDebug.log("[Open AI] \(message)")
        return message
    }
}
