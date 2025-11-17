//
//  EvolutionListService+Test.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies
import Foundation
import XCTestDynamicOverlay
import ComposableArchitecture

extension EvolutionListService: TestDependencyKey {
    static let testValue = Self(
        loadEvolutionList: unimplemented("\(Self.self).loadEvolutionList"),
        removeItem: unimplemented("\(Self.self).removeItem")
    )

    static let previewValue = Self(
        loadEvolutionList: {
            [
                .init(
                    id: UUID(uuidString: "9361BB92-83EF-49B9-921F-359C66691D02")!,
                    name: "Switch1",
                    active: false,
                    onCommand: EvolutionCommand(executeType: .shell, commandType: .on, commandString: "pwd"),
                    offCommand: EvolutionCommand(executeType: .shell, commandType: .off, commandString: "pwd"),
                    statusCommand: EvolutionCommand(executeType: .shell, commandType: .status, commandString: "pwd")
                ),
                .init(
                    id: UUID(uuidString: "B8B8C5D9-16B6-4F9F-B634-B27C7F4A5FA3")!,
                    name: "Runner1",
                    active: true,
                    controlType: .Button
                ),
                .init(
                    id: UUID(uuidString: "9B9BCF16-3F6D-400F-9714-BDD9A548D4A5")!, name: "Switch2", active: false
                )
            ]
        },
        removeItem: { _ in }
    )
}
