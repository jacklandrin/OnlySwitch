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
