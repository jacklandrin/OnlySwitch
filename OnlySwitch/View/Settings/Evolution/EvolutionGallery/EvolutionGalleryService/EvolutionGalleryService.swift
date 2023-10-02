//
//  EvolutionGalleryService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import Foundation

struct EvolutionGalleryService {
    var fetchGalleryList: @Sendable () async throws -> [EvolutionGalleryItem]
    var checkInstallation: (UUID) -> Bool
    var addGallery: @Sendable (EvolutionItem) async throws -> Void
}
