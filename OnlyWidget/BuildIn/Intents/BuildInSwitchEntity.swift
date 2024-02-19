//
//  SwitchEntity.swift
//
//
//  Created by Jacklandrin on 2024/2/18.
//

import AppIntents
import Switches

struct BuildInSwitchEntity: AppEntity {
    var id: String
    var type: SwitchType
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Build-In Switch"
    static var defaultQuery = BuildInSwitchQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(type.barInfo().title)")
    }

    static var allSwitches: [BuildInSwitchEntity] {
        let switches = SwitchType.allCases.filter{ !exceptionSwitches.contains($0) }
        return switches.map { BuildInSwitchEntity(id: String($0.rawValue), type: $0) }
    }

    private static var exceptionSwitches: [SwitchType] {
        [.topNotch, .airPods, .applemusic, .spotify, .screenTest]
    }
}

struct BuildInSwitchQuery: EntityQuery {
    func entities(for identifiers: [BuildInSwitchEntity.ID]) async throws -> [BuildInSwitchEntity] {
        BuildInSwitchEntity.allSwitches.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BuildInSwitchEntity] {
        BuildInSwitchEntity.allSwitches
    }

    func defaultResult() async -> BuildInSwitchEntity? {
        BuildInSwitchEntity.allSwitches.first
    }

    func defaultResult() -> BuildInSwitchEntity? {
        BuildInSwitchEntity.allSwitches.first
    }
}
