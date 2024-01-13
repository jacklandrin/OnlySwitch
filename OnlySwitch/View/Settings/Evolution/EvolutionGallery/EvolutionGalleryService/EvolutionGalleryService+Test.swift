//
//  EvolutionGalleryService+Test.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import Dependencies
import Foundation
import XCTestDynamicOverlay

extension EvolutionGalleryService: TestDependencyKey {
    static let testValue = Self(
        fetchGalleryList: unimplemented("\(Self.self).fetchGalleryList"),
        checkInstallation: unimplemented("\(Self.self).checkInstallation"),
        addGallery: unimplemented("\(Self.self).addGallery")
    )
}

extension EvolutionGalleryService {
    static let mockValue = Self(
        fetchGalleryList: {
            guard let url = Bundle.main.url(forResource: "EvolutionMarket", withExtension: "json") else {
                print("json file not found")
                return []
            }
            let data = try Data(contentsOf: url)
            let evolutionGalleryModels = try JSONDecoder().decode([EvolutionGalleryModel].self, from: data)
            return EvolutionGalleryAdaptor.convertToGallery(from: evolutionGalleryModels)
        }, checkInstallation: (
            liveValue.checkInstallation
        ), addGallery: (
            liveValue.addGallery
        )
    )
}
