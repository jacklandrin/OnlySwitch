//
//  EvolutionGalleryService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import Foundation
import Dependencies
import DependenciesMacros

@DependencyClient
struct EvolutionGalleryService: Sendable {
    var fetchGalleryList: @Sendable () async throws -> [EvolutionGalleryItem] = { [] }
    var checkInstallation: @Sendable (UUID) -> Bool = { _ in false }
    var addGallery: @Sendable (EvolutionItem) async throws -> Void
}
