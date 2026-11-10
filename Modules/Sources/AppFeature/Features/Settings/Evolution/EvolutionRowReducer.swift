//
//  EvolutionRowReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/11.
//

import ComposableArchitecture
import Foundation

/// One Evolution in the sidebar: its name, icon and whether it is shown in the menu.
@Reducer
struct EvolutionRowReducer {
    @ObservableState
    struct State: Equatable, Identifiable {
        var evolution: EvolutionItem

        var id: UUID { evolution.id }

        init(evolution: EvolutionItem) {
            self.evolution = evolution
        }
    }

    @CasePathable
    enum Action: Equatable {
        case setActive(Bool)
    }

    @Dependency(\.evolutionListService) var evolutionListService

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setActive(isActive):
                guard state.evolution.active != isActive else { return .none }
                state.evolution.active = isActive
                let id = state.id
                let service = evolutionListService
                return .run { _ in
                    await service.setActive(id, isActive)
                }
            }
        }
    }
}
