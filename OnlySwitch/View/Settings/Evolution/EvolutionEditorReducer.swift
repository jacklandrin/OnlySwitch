//
//  EvolutionEditorReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import ComposableArchitecture
import Foundation

struct EvolutionEditorReducer: ReducerProtocol {

    struct State: Equatable, Identifiable {
        var id: UUID
        var evolution: EvolutionItem
        var onCommandState = EvolutionCommandEditingReducer.State(type: .on)
        var offCommandState = EvolutionCommandEditingReducer.State(type: .off)
        var singleCommandState = EvolutionCommandEditingReducer.State(type: .single)
        var statusCommandState = EvolutionCommandEditingReducer.State(type: .status)

        init(evolution: EvolutionItem? = nil) {
            if let evolution {
                self.evolution = evolution
            } else {
                self.evolution = EvolutionItem()
            }
            self.id = self.evolution.id
        }
    }

    enum Action: Equatable, Sendable {
        case toggleItem
        case changeName(String)
        case changeType(ControlType)
        case save
        case delegate(Delegate)
        case commandAction(EvolutionCommandEditingReducer.Action)
        enum Delegate: Equatable {
            case goback
        }
    }


    var body: some ReducerProtocolOf<Self> {
        Scope(state: \.onCommandState, action: /Action.commandAction) {
            EvolutionCommandEditingReducer()
        }

        Scope(state: \.offCommandState, action: /Action.commandAction) {
            EvolutionCommandEditingReducer()
        }

        Scope(state: \.singleCommandState, action: /Action.commandAction) {
            EvolutionCommandEditingReducer()
        }

        Scope(state: \.statusCommandState, action: /Action.commandAction) {
            EvolutionCommandEditingReducer()
        }

        Reduce { state, action in
            switch action {
                case .toggleItem:
                    state.evolution.active.toggle()
                    return .none

                case let .changeName(name):
                    state.evolution.name = name
                    return .none
                    
                case let .changeType(type):
                    state.evolution.controlType = type
                    return .none

                case .save:

                    return .run { send in
                        await send(.delegate(.goback))
                    }

                case .delegate:
                    return .none

                case .commandAction:
                    return .none
            }
        }
    }
}
