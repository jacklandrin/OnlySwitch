//
//  Evolution+Dependencies.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Dependencies

extension DependencyValues {
    var evolutionListService: EvolutionListService {
        get { self[EvolutionListService.self] }
        set { self[EvolutionListService.self] = newValue }
    }

    var evolutionEditorService: EvolutionEditorService {
        get { self[EvolutionEditorService.self] }
        set { self[EvolutionEditorService.self] = newValue }
    }
}
