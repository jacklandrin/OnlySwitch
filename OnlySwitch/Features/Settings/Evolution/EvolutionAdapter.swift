//
//  EvolutionAdapter.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/4.
//

import Foundation
import Switches

struct EvolutionAdapter {

    static func evolutionItems(_ enities: [EvolutionCommandEntity]) -> [EvolutionItem] {
        enities
            .compactMap {
                toEvolutionItem($0)
            }
    }

    static func toEvolutionItem(_ entity: EvolutionCommandEntity) -> EvolutionItem? {
        guard let id = entity.id,
              let name = entity.name,
              let itemTypeStr = entity.itemType,
              let controlType = ControlType(rawValue: itemTypeStr) else {
            return nil
        }

        var item = EvolutionItem(
            id: id,
            name: name,
            controlType: controlType
        )

        if
            let onCommandStr = entity.turnOnCommand,
            let onCommandTypeStr = entity.turnOnCommandType,
            let onCommandType = CommandExecuteType(rawValue: onCommandTypeStr)
        {
            item.onCommand = EvolutionCommand(
                executeType: onCommandType,
                commandType: .on,
                commandString: onCommandStr
            )
        }

        if
            let offCommandStr = entity.turnOffCommand,
            let offCommandTypeStr = entity.turnOffCommandType,
            let offCommandType = CommandExecuteType(rawValue: offCommandTypeStr)
        {
            item.offCommand = EvolutionCommand(
                executeType: offCommandType,
                commandType: .off,
                commandString: offCommandStr
            )
        }

        if
            let statusCommandStr = entity.statusCommand,
            let statusCommandTypeStr = entity.statusCommandType,
            let statusCommandType = CommandExecuteType(rawValue: statusCommandTypeStr)
        {
            item.statusCommand = EvolutionCommand(
                executeType: statusCommandType,
                commandType: .status,
                commandString: statusCommandStr
            )
        }

        if
            let singleCommandStr = entity.singleCommand,
            let singleCommandTypeStr = entity.singleCommandType,
            let singleCommandType = CommandExecuteType(rawValue: singleCommandTypeStr)
        {
            item.singleCommand = EvolutionCommand(
                executeType: singleCommandType,
                commandType: .single,
                commandString: singleCommandStr
            )
        }

        if let trueCondition = entity.trueCondition {
            item.statusCommand?.trueCondition = trueCondition
        }

        if let iconName = entity.iconName {
            item.iconName = iconName
        }
        
        return item
    }
}
