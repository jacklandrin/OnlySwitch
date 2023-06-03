//
//  EvolutionEditorService+Test.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies
import Foundation
import XCTestDynamicOverlay

extension EvolutionEditorService: TestDependencyKey {
    static let testValue = Self(
        executeCommand: unimplemented("\(Self.self).executeCommand")
    )
}
