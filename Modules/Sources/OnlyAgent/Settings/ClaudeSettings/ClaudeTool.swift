//
//  ClaudeTool.swift
//  Modules
//
//  Created by Louis Saks on 23.06.26.
//

import OSLog
import Foundation
import Dependencies

@available(macOS 26.0, *)
final class ClaudeTool: ModelTool {
    func call(arguments: ToolArguments) async throws -> String {
        @Dependency(\.modelProviderService) var modelProviderService
        Logger.onlyAgentDebug.log("[Claude] model: \(arguments.model)\n prompt: \(arguments.prompt)")
        let message = try await modelProviderService.chat(.claude, arguments.model, arguments.prompt)
        Logger.onlyAgentDebug.log("[Claude] \(message)")
        return message
    }
}
