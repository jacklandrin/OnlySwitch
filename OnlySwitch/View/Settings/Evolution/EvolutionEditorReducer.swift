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
        var showError = false

        init(evolution: EvolutionItem? = nil) {
            if let evolution {
                self.evolution = evolution
            } else {
                self.evolution = EvolutionItem()
            }
            self.id = self.evolution.id
            if let onCommand = evolution?.onCommand {
                self.onCommandState.command = onCommand
            }

            if let offCommand = evolution?.offCommand {
                self.offCommandState.command = offCommand
            }

            if let singleCommand = evolution?.singleCommand {
                self.singleCommandState.command = singleCommand
            }

            if let statusCommand = evolution?.statusCommand {
                self.statusCommandState.command = statusCommand
            }
        }
    }

    enum Action: Equatable, Sendable {
        static func == (lhs: EvolutionEditorReducer.Action, rhs: EvolutionEditorReducer.Action) -> Bool {
            switch (lhs, rhs) {
                case (.finishSave(_), .finishSave(_)):
                    return false
                default:
                    return lhs == rhs
            }
        }

        case toggleItem
        case changeName(String)
        case changeType(ControlType)
        case save
        case finishSave(TaskResult<Void>)
        case errorControl(Bool)
        case delegate(Delegate)
        case commandAction(EvolutionCommandEditingReducer.Action)
        enum Delegate: Equatable {
            case goback
        }
    }

    @Dependency(\.evolutionEditorService) var evolutionEditorService

    var body: some ReducerProtocolOf<Self> {

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
//                    return .task { [item = state.evolution] in
//                        return await .finishSave(
//                            TaskResult {
//                                return try await evolutionEditorService.saveCommand(item)
//                            }
//                        )
//                    }
                    return .send(.delegate(.goback))

                case .finishSave(.success):
                    return .run { send in
                        await send(.delegate(.goback))
                    }

                case .finishSave(.failure(_)):
                    return .run { send in
                        await send(.errorControl(true))
                    }

                case let .errorControl(show):
                    state.showError = show
                    return .none

                case .delegate:
                    return .none

                case .commandAction:
                    return .none
            }
        }
    }
}
