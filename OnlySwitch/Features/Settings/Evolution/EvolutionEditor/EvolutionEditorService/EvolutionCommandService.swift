//
//  EvolutionEditorService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Foundation
import Dependencies

struct EvolutionCommandService {
    var executeCommand: @Sendable (EvolutionCommand?) async throws -> String
    var saveCommand: @Sendable (EvolutionItem) async throws -> Void
    var saveIcon: @Sendable (UUID, String) async throws -> Void
}

extension EvolutionCommandService {
    /// Executes a switch Evolution without deriving privilege from its command text.
    /// Only a previously validated, curated operation identifier may use the helper.
    func executeSwitch(_ item: EvolutionItem, enabled: Bool) async throws -> String {
        if let operation = EvolutionItem.trustedPrivilegedOperation(
            id: item.id,
            controlType: item.controlType,
            requestedOperation: item.privilegedOperation
        ) {
            @Dependency(\.privilegedOperationClient) var privilegedOperationClient
            try await privilegedOperationClient.perform(operation, enabled)
            return ""
        }

        return try await executeCommand(enabled ? item.onCommand : item.offCommand)
    }
}
