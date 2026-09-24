//
//  EvolutionCommandEntityLive.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/6/9.
//

import Extensions
import Foundation
import Switches

extension EvolutionCommandEntity {
    @MainActor static func backupCommands() throws -> [[String: String]] {
        try fetchResult().map { entity in
            var command: [String: String] = [:]
            for key in EvolutionBackup.commandKeys {
                switch entity.value(forKey: key) {
                case let uuid as UUID: command[key] = uuid.uuidString
                case let string as String: command[key] = string
                default: break
                }
            }
            return command
        }
    }

    /// Stores commands without running them. The privileged operation is re-derived from the
    /// compiled allowlist, so an imported file can't grant itself privileged-helper access.
    static func restore(_ commands: [[String: String]]) throws {
        for command in commands {
            guard
                let id = command["id"].flatMap(UUID.init(uuidString:)),
                let name = command["name"], !name.isEmpty,
                let controlType = command["itemType"].flatMap(ControlType.init(rawValue:))
            else {
                continue
            }
            let entity = try fetchRequest(by: id) ?? EvolutionCommandEntity(context: context)
            for key in EvolutionBackup.commandKeys where key != "id" && key != "privilegedOperationIdentifier" {
                entity.setValue(command[key], forKey: key)
            }
            entity.id = id
            entity.privilegedOperationIdentifier = EvolutionItem.trustedPrivilegedOperation(
                id: id,
                controlType: controlType,
                requestedOperation: command["privilegedOperationIdentifier"].flatMap(PrivilegedOperation.init(rawValue:))
            )?.rawValue
            entity.timestamp = Date()
        }
        if context.hasChanges {
            try context.save()
        }
    }

    static func addItem(item: EvolutionItem) throws {
        let entity = try EvolutionCommandEntity.fetchRequest(by: item.id) ?? EvolutionCommandEntity(context: context)

        if item.controlType == .Button {
            guard
                let singleCommand = item.singleCommand?.commandString,
                !singleCommand.isEmpty,
                let singleCommandTypeStr = item.singleCommand?.executeType.rawValue,
                item.singleCommand?.debugStatus == .success else {
                    context.reset()
                    throw EvolutionError.wrongCommand
                }
            entity.singleCommand = singleCommand
            entity.singleCommandType = singleCommandTypeStr

            entity.turnOnCommand = ""
            entity.turnOnCommandType = CommandExecuteType.shell.rawValue

            entity.turnOffCommand = ""
            entity.turnOffCommandType = CommandExecuteType.shell.rawValue

            entity.statusCommand = ""
            entity.statusCommandType = CommandExecuteType.shell.rawValue

            entity.trueCondition = ""

        } else {
            guard
                let onCommand = item.onCommand?.commandString,
                !onCommand.isEmpty,
                let onCommandTypeStr = item.onCommand?.executeType.rawValue,
                item.onCommand?.debugStatus == .success else {
                context.reset()
                throw EvolutionError.wrongCommand
            }
            entity.turnOnCommand = onCommand
            entity.turnOnCommandType = onCommandTypeStr

            guard
                let offCommand = item.offCommand?.commandString,
                !offCommand.isEmpty,
                let offCommandTypeStr = item.offCommand?.executeType.rawValue,
                item.offCommand?.debugStatus == .success else {
                context.reset()
                throw EvolutionError.wrongCommand
            }

            entity.turnOffCommand = offCommand
            entity.turnOffCommandType = offCommandTypeStr

            guard
                let statusCommand = item.statusCommand?.commandString,
                !statusCommand.isEmpty,
                let statusCommandTypeStr = item.statusCommand?.executeType.rawValue,
                let trueCondition = item.statusCommand?.trueCondition else {
                context.reset()
                throw EvolutionError.wrongCommand
            }
            entity.statusCommand = statusCommand
            entity.statusCommandType = statusCommandTypeStr
            entity.trueCondition = trueCondition

            entity.singleCommand = ""
            entity.singleCommandType = CommandExecuteType.shell.rawValue
        }

        if let iconName = item.iconName {
            entity.iconName = iconName
        }

        entity.name = item.name
        entity.itemType = item.controlType.rawValue
        entity.privilegedOperationIdentifier = EvolutionItem.trustedPrivilegedOperation(
            id: item.id,
            controlType: item.controlType,
            requestedOperation: item.privilegedOperation
        )?.rawValue
        entity.timestamp = Date()
        entity.id = item.id


        try context.save()
    }

    static func updateIcon(name: String, by id: UUID) throws {
        let entity = try EvolutionCommandEntity.fetchRequest(by: id)
        guard let entity else {
            throw EvolutionError.noneEntity
        }
        entity.iconName = name
        try context.save()
    }

    static func removeItem(by id: UUID) throws {
        guard let entity = try fetchRequest(by: id) else {
            throw EvolutionError.deleteFailed
        }

        context.delete(entity)
        try context.save()
    }
}
