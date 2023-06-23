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
        var commandStates: IdentifiedArrayOf<EvolutionCommandEditingReducer.State>
        var switchCommandStates:IdentifiedArrayOf<EvolutionCommandEditingReducer.State>
        var buttonCommandStates:IdentifiedArrayOf<EvolutionCommandEditingReducer.State>

        var showError = false
        var showIconNamesPopover = false

        init(evolution: EvolutionItem? = nil) {
            if let evolution {
                self.evolution = evolution
            } else {
                self.evolution = EvolutionItem()
            }
            self.id = self.evolution.id
            self.switchCommandStates = [
                EvolutionCommandEditingReducer.State(type: .on, command: self.evolution.onCommand),
                EvolutionCommandEditingReducer.State(type: .off, command: self.evolution.offCommand),
                EvolutionCommandEditingReducer.State(type: .status, command: self.evolution.statusCommand)
            ]
            self.buttonCommandStates = [
                EvolutionCommandEditingReducer.State(type: .single, command: self.evolution.singleCommand),
            ]
            if self.evolution.controlType == .Switch {
                self.commandStates = switchCommandStates
            } else {
                self.commandStates = buttonCommandStates
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
        case toggleIconNamesPopover(Bool)
        case selectIcon(String)
        case changeType(ControlType)
        case save
        case finishSave(TaskResult<Void>)
        case errorControl(Bool)
        case delegate(Delegate)
        case commandAction(id: UUID, action: EvolutionCommandEditingReducer.Action)
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

                case let .toggleIconNamesPopover(shouldShow):
                    state.showIconNamesPopover = shouldShow
                    return .none

                case let .selectIcon(name):
                    state.evolution.iconName = name
                    return .none

                case let .changeType(type):
                    state.evolution.controlType = type
                    switch type {
                        case .Switch:
                            state.commandStates = state.switchCommandStates

                        case .Button:
                            state.commandStates = state.buttonCommandStates

                        default:
                            break
                    }
                    return .none

                case .save:
                    switch state.evolution.controlType {
                        case .Button:
                            state.evolution.singleCommand = state.commandStates.first{ $0.command.commandType == .single }?.command

                        case .Switch:
                            state.evolution.onCommand = state.commandStates.first{ $0.command.commandType == .on }?.command
                            state.evolution.offCommand = state.commandStates.first{ $0.command.commandType == .off }?.command
                            state.evolution.statusCommand = state.commandStates.first{ $0.command.commandType == .status }?.command

                        default:
                            break
                    }
                    return .task { [item = state.evolution] in
                        return await .finishSave(
                            TaskResult {
                                return try await evolutionEditorService.saveCommand(item)
                            }
                        )
                    }

                case .finishSave(.success):
                    return .run { @MainActor send in
                        send(.delegate(.goback))
                    }

                case .finishSave(.failure(_)):
                    return .run { @MainActor send in
                        send(.errorControl(true))
                    }

                case let .errorControl(show):
                    state.showError = show
                    return .none

                case .delegate:
                    return .none

                case let .commandAction(id:_ , action: .delegate(command)):
                    switch command.commandType {
                        case .on:
                            state.evolution.onCommand = command

                        case .off:
                            state.evolution.onCommand = command

                        case .single:
                            state.evolution.singleCommand = command

                        case .status:
                            state.evolution.statusCommand = command
                    }
                    return .none

                case .commandAction:
                    return .none
            }
        }
        .forEach(\.commandStates, action: /Action.commandAction) {
            EvolutionCommandEditingReducer()
        }
    }
}
