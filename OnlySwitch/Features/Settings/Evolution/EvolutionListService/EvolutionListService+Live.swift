//
//  EvolutionListService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies
import Extensions
import Switches

extension EvolutionListService: DependencyKey {
    static let liveValue = Self(
        loadEvolutionList: {
            try await MainActor.run {
                let entities = try EvolutionCommandEntity.fetchResult()
                let context = PersistenceController
                    .shared
                    .container
                    .viewContext
                let uniqueEntities = entities.unique { $0.id }
                let unneededEntities = entities.filter { entity in
                    !uniqueEntities.contains { $0.objectID == entity.objectID }
                }
                unneededEntities.forEach { entity in
                    context.delete(entity)
                }

                // Clamshell existed before privileged operation IDs were
                // persisted. Upgrade only the exact compiled gallery item so
                // an existing installation stops executing its legacy sudo
                // command. User-created Evolutions never receive helper access.
                uniqueEntities.forEach { entity in
                    guard
                        // Older Core Data records may represent an unset
                        // optional text value as either nil or an empty string.
                        entity.privilegedOperationIdentifier?.isEmpty != false,
                        let id = entity.id,
                        let itemType = entity.itemType,
                        let controlType = ControlType(rawValue: itemType),
                        let operation = EvolutionItem.curatedPrivilegedOperation(
                            id: id,
                            controlType: controlType
                        )
                    else {
                        return
                    }

                    entity.privilegedOperationIdentifier = operation.rawValue
                }
                try context.save()
                return EvolutionAdapter.evolutionItems(uniqueEntities)
            }
        },
        removeItem: { id in
            try EvolutionCommandEntity.removeItem(by: id)
            guard let evolutionIDs = UserDefaults.standard.array(forKey: UserDefaults.Key.evolutionIDs) as? [String] else {
                UserDefaults.standard.setValue([String](), forKey: UserDefaults.Key.evolutionIDs)
                return
            }
            let idString = id.uuidString
            var newEvolutionIDs = evolutionIDs

            if let index = evolutionIDs.firstIndex(of: idString) {
                newEvolutionIDs.remove(at: index)
            }
        }
    )
}
