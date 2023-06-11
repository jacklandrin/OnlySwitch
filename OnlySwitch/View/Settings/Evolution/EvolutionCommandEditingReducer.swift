//
//  EvolutionCommandEditingReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/29.
//

import Foundation
import ComposableArchitecture

struct EvolutionCommandEditingReducer: ReducerProtocol {
    struct State: Equatable {
        var command: EvolutionCommand

        init(type: CommandType) {
            self.command = EvolutionCommand(commandType: type)
        }
    }

    enum Action: Equatable {
        case editCommand(String)
        case returnCommandString
        case changeExecuteType(CommandExecuteType)
        case shouldTest
        case testCommand(TaskResult<String>)
    }

    @Dependency(\.evolutionEditorService) var evolutionEditorService

    var body: some ReducerProtocolOf<Self> {
        Reduce { state, action in
            switch action {
                case let .editCommand(command):
                    state.command.commandString = command
                    return .none

                case .returnCommandString:
                    state.command.commandString += "\r\n"
                    return .none

                case let .changeExecuteType(type):
                    state.command.executeType = type
                    return .none

                case .shouldTest:
                    return .task { [command = state.command] in
                        return await .testCommand(
                            TaskResult { @MainActor in
                                try evolutionEditorService.executeCommand(command)
                            }
                        )
                    }

                case .testCommand(.success(_)):
                    state.command.debugStatus = .success
                    return .none

                case .testCommand(.failure(_)):
                    state.command.debugStatus = .failed
                    return .none
            }
        }
    }
}
