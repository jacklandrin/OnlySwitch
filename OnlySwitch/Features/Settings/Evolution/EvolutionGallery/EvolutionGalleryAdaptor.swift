//
//  EvolutionGalleryAdaptor.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import Foundation
import Switches

struct EvolutionGalleryAdaptor {
    /// A catalogue response is not sufficient authority to add a root operation.
    /// Bind each permitted operation to its stable, shipped gallery item identifier.
    private static let curatedOperations: [UUID: PrivilegedOperation] = [
        UUID(uuidString: "0AD2A1A8-E0BA-4F6A-9E28-2E2B06143C8D")!: .clamshellSleepDisabled
    ]

    static func convertToGalleryItem(from model: EvolutionGalleryModel) -> EvolutionGalleryItem {
        var evolutionItem = EvolutionItem()
        evolutionItem.id = UUID(uuidString: model.id) ?? UUID()
        evolutionItem.name = model.name
        evolutionItem.iconName = model.icon_name
        evolutionItem.controlType = ControlType(rawValue: model.type) ?? .Switch
        if let expectedOperation = curatedOperations[evolutionItem.id],
           model.privileged_operation == expectedOperation.rawValue {
            evolutionItem.privilegedOperation = expectedOperation
        }

        if evolutionItem.controlType == .Switch {
            if let on_command = model.on_command {
                evolutionItem.onCommand = EvolutionCommand(commandType: .on)
                evolutionItem.onCommand?.commandString = on_command.command
                evolutionItem.onCommand?.executeType = CommandExecuteType(rawValue: on_command.type) ?? .shell
                evolutionItem.onCommand?.debugStatus = .success
            }

            if let off_command = model.off_command {
                evolutionItem.offCommand = EvolutionCommand(commandType: .off)
                evolutionItem.offCommand?.commandString = off_command.command
                evolutionItem.offCommand?.executeType = CommandExecuteType(rawValue: off_command.type) ?? .shell
                evolutionItem.offCommand?.debugStatus = .success
            }

            if let check_command = model.check_command {
                evolutionItem.statusCommand = EvolutionCommand(commandType: .status)
                evolutionItem.statusCommand?.commandString = check_command.command
                evolutionItem.statusCommand?.executeType = CommandExecuteType(rawValue: check_command.type) ?? .shell
                evolutionItem.statusCommand?.trueCondition = check_command.true_condition
                evolutionItem.statusCommand?.debugStatus = .success
            }
        } else {
            if let single_command = model.single_command {
                evolutionItem.singleCommand = EvolutionCommand(commandType: .single)
                evolutionItem.singleCommand?.commandString = single_command.command
                evolutionItem.singleCommand?.executeType = CommandExecuteType(rawValue: single_command.type) ?? .shell
                evolutionItem.singleCommand?.debugStatus = .success
            }
        }

        return EvolutionGalleryItem(
            evolution: evolutionItem,
            author: model.author,
            description: model.description
        )
    }

    static func convertToGallery(from models: [EvolutionGalleryModel]) -> [EvolutionGalleryItem] {
        models.map {
            Self.convertToGalleryItem(from: $0)
        }
    }
}
