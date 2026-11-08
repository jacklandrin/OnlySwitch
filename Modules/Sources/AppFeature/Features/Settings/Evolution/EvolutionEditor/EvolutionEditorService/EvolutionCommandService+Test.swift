//
//  EvolutionEditorService+Test.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies
import Foundation
import XCTestDynamicOverlay

extension EvolutionCommandService: TestDependencyKey {
    static let testValue = Self(
        executeCommand: unimplemented("\(Self.self).executeCommand"),
        saveCommand: unimplemented("\(Self.self).saveCommand"),
        saveIcon: unimplemented("\(Self.self).saveIcon")
    )
}
