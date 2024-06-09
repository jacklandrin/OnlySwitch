//
//  EvolutionListService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies
import Extensions

extension EvolutionListService: DependencyKey {
    static let liveValue = Self(
        loadEvolutionList: {
            let entities = try await EvolutionCommandEntity.fetchResult()
            let context = PersistenceController
                .shared
                .container
                .viewContext
            var uniqueEntities = entities.unique { $0.id }
            let unneededEntities = entities.filter { entity in
                !uniqueEntities.contains { $0.objectID == entity.objectID }
            }
            unneededEntities.forEach { entity in
                context.delete(entity)
            }
            try context.save()
            return EvolutionAdapter.evolutionItems(uniqueEntities)
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

