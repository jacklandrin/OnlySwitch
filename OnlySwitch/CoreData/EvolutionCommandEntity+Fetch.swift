//
//  EvolutionCommandEntity+Fetch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/4.
//

import CoreData
import Foundation

extension EvolutionCommandEntity {

    @MainActor static var defaultFetchRequest:NSFetchRequest<EvolutionCommandEntity> {
        let request:NSFetchRequest<EvolutionCommandEntity> = EvolutionCommandEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EvolutionCommandEntity.timestamp, ascending: false)]
        print("fetched the evolution command")
        return request
    }

    @MainActor static func fetchResult() throws -> [EvolutionCommandEntity] {
        try PersistenceController
            .shared
            .container
            .viewContext
            .fetch(EvolutionCommandEntity.defaultFetchRequest)
    }

    static func fetchRequest(by id: UUID) throws -> EvolutionCommandEntity? {
        let predicate = NSPredicate(
            format: "%K = %@", "id" , "\(id)"
        )

        let request = EvolutionCommandEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EvolutionCommandEntity.timestamp, ascending: true)]
        request.predicate = predicate

        return try PersistenceController
            .shared
            .container
            .viewContext
            .fetch(request)
            .first
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

    static var context: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }
}
