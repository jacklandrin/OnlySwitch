//
//  EvolutionListService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies

extension EvolutionListService: DependencyKey {
    static let liveValue = Self(
        loadEvolutionList: {
            let entities = try EvolutionCommandEntity.fetchResult()
//            let context = PersistenceController
//                .shared
//                .container
//                .viewContext
//            for entity in entities {
//                context.delete(entity)
//            }
//            try context.save()
            return EvolutionAdapter.evolutionItems(entities)
        },
        removeItem: { id in
            try EvolutionCommandEntity.removeItem(by: id)
        }
    )
}
