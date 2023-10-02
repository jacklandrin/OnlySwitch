//
//  EvolutionGalleryService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import Foundation
import Dependencies

extension EvolutionGalleryService: DependencyKey {
    static var liveValue = Self(
        fetchGalleryList: {
            guard let url = Bundle.main.url(forResource: "EvolutionMarket", withExtension: "json") else {
                print("json file not found")
                return []
            }
            let data = try Data(contentsOf: url)
            let evolutionGalleryModels = try JSONDecoder().decode([EvolutionGalleryModel].self, from: data)
            return EvolutionGalleryAdaptor.convertToGallery(from: evolutionGalleryModels)
        },
        checkInstallation: { id in
            do {
                guard let entity = try EvolutionCommandEntity.fetchRequest(by: id) else {
                    return false
                }
                return true
            } catch {
                return false
            }
        },
        addGallery: { item in
            try EvolutionCommandEntity.addItem(item: item)
        }
    )
}
