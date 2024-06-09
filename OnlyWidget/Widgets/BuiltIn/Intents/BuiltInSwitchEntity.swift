//
//  SwitchEntity.swift
//
//
//  Created by Jacklandrin on 2024/2/18.
//

import AppIntents
import Switches
import Extensions

struct BuiltInSwitchEntity: AppEntity {
    var id: String
    var type: SwitchType
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Built-In Switch"
    static var defaultQuery = BuildInSwitchQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(type.barInfo().title.localized())")
    }

    static var allSwitches: [BuiltInSwitchEntity] {
        let switches = SwitchType.allCases.filter{ !exceptionSwitches.contains($0) }
        return switches.map { BuiltInSwitchEntity(id: String($0.rawValue), type: $0) }
    }

    private static var exceptionSwitches: [SwitchType] {
        [.topNotch, .airPods, .applemusic, .spotify, .screenTest]
    }
}

struct BuildInSwitchQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [BuiltInSwitchEntity] {
        BuiltInSwitchEntity.allSwitches
            .filter {
                $0.type.barInfo().title.range(of: string, options: .caseInsensitive) != nil
            }
    }

    func entities(for identifiers: [BuiltInSwitchEntity.ID]) async throws -> [BuiltInSwitchEntity] {
        BuiltInSwitchEntity.allSwitches.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BuiltInSwitchEntity] {
        BuiltInSwitchEntity.allSwitches
    }

    func defaultResult() async -> BuiltInSwitchEntity? {
        BuiltInSwitchEntity.allSwitches.first
    }

    func defaultResult() -> BuiltInSwitchEntity? {
        BuiltInSwitchEntity.allSwitches.first
    }
}
