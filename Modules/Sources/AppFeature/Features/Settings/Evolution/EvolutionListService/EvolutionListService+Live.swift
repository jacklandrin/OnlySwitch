//
//  EvolutionListService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies
import Extensions
import Switches
import OnlySwitchPersistence
import Foundation
import KeyboardShortcuts

extension EvolutionListService: DependencyKey {
    static let liveValue = Self(
        loadEvolutionList: {
            try await MainActor.run {
                try PersistenceController.shared.requireStore()
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
                let activeIDs = Set(UserDefaults.standard.array(forKey: UserDefaults.Key.evolutionIDs) as? [String] ?? [])
                return EvolutionAdapter.evolutionItems(uniqueEntities).map { item in
                    var item = item
                    item.active = activeIDs.contains(item.id.uuidString)
                    return item
                }
            }
        },
        removeItem: { id in
            try EvolutionCommandEntity.removeItem(by: id)
            let idString = id.uuidString
            let ids = (UserDefaults.standard.array(forKey: UserDefaults.Key.evolutionIDs) as? [String]) ?? []
            UserDefaults.standard.set(ids.filter { $0 != idString }, forKey: UserDefaults.Key.evolutionIDs)
            await MainActor.run {
                KeyboardShortcuts.reset(KeyboardShortcuts.Name(idString))
                NotificationCenter.default.post(name: .changeSettings, object: nil)
            }
        },
        setActive: { id, isActive in
            // The menu reads this list of IDs; its key and format are unchanged.
            let idString = id.uuidString
            var ids = (UserDefaults.standard.array(forKey: UserDefaults.Key.evolutionIDs) as? [String]) ?? []
            if isActive {
                // Keep the existing position so the menu order doesn't change.
                if !ids.contains(idString) { ids.append(idString) }
            } else {
                ids.removeAll { $0 == idString }
            }
            UserDefaults.standard.set(ids, forKey: UserDefaults.Key.evolutionIDs)
            await MainActor.run {
                NotificationCenter.default.post(name: .changeSettings, object: nil)
            }
        }
    )
}
