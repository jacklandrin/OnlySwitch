//
//  EvolutionCommandEditingReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/29.
//

import Foundation
import ComposableArchitecture

struct EvolutionCommandEditingReducer: Reducer {
    struct State: Equatable, Identifiable {
        var id = UUID()
        var command: EvolutionCommand
        var statusCommandResult = ""
        init(type: CommandType, command: EvolutionCommand?) {
            if let command {
                self.command = command
            } else {
                self.command = EvolutionCommand(commandType: type)
            }
        }
    }

    enum Action: Equatable {
        case editCommand(String)
        case editTrueCondition(String)
        case returnCommandString
        case changeExecuteType(CommandExecuteType)
        case shouldTest
        case testCommand(TaskResult<String>)
        case delegate(EvolutionCommand)
    }

    @Dependency(\.evolutionEditorService) var evolutionEditorService

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case let .editCommand(command):
                    state.command.commandString = command
                    return .none

                case let .editTrueCondition(condition):
                    state.command.trueCondition = condition
                    return .none

                case .returnCommandString:
                    state.command.commandString += "\r\n"
                    return .none

                case let .changeExecuteType(type):
                    state.command.executeType = type
                    return .none

                case .shouldTest:
                    return .run { [command = state.command] send in
                        return await send(
                            .testCommand(
                                TaskResult { @MainActor in
                                    try evolutionEditorService.executeCommand(command)
                                }
                            )
                        )
                    }

                case let .testCommand(.success(result)):
                    state.command.debugStatus = .success
                    state.statusCommandResult = result
                    return .send(.delegate(state.command))

                case .testCommand(.failure(_)):
                    state.command.debugStatus = .failed
                    return .none

                case .delegate:
                    return .none
            }
        }
    }
}
