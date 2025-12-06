//
//  GeminiTool.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

import OSLog
import Foundation
import Dependencies

final class GeminiTool: ModelTool {
    func call(arguments: ToolArguments) async throws -> String {
        @Dependency(\.geminiService) var geminiService
        Logger.onlyAgentDebug.log("[Gemini] model: \(arguments.model)\n prompt: \(arguments.prompt)")

        let message = try await geminiService.chat(arguments.model, arguments.prompt)
        Logger.onlyAgentDebug.log("[Gemini] \(message)")
        return message
    }
}
