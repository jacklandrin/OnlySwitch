//
//  EvolutionCommandEditingReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/29.
//

import ComposableArchitecture
import Foundation

@Reducer
struct EvolutionCommandEditingReducer {
    @ObservableState
    struct State: Equatable, Identifiable {
        var command: EvolutionCommand
        /// Raw output of the last successful test.
        var lastOutput: String?
        var errorMessage: String?
        var isTesting = false

        var id: CommandType { command.commandType }

        init(type: CommandType, command: EvolutionCommand?) {
            self.command = command ?? EvolutionCommand(commandType: type)
        }
    }

    struct TestFailure: Error, Equatable {
        let message: String
    }

    @CasePathable
    enum Action: Equatable {
        case editCommand(String)
        case editTrueCondition(String)
        case useLastOutput
        case changeExecuteType(CommandExecuteType)
        case testTapped
        case testFinished(Result<String, TestFailure>)
    }

    @Dependency(\.evolutionCommandService) var evolutionCommandService

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .editCommand(command):
                guard state.command.commandString != command else { return .none }
                state.command.commandString = command
                state.resetTestResult()
                return .none

            case let .editTrueCondition(condition):
                state.command.trueCondition = condition
                return .none

            case .useLastOutput:
                if let lastOutput = state.lastOutput {
                    state.command.trueCondition = lastOutput
                }
                return .none

            case let .changeExecuteType(type):
                guard state.command.executeType != type else { return .none }
                state.command.executeType = type
                state.resetTestResult()
                return .none

            case .testTapped:
                guard !state.isTesting,
                      !state.command.commandString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return .none
                }
                state.isTesting = true
                state.errorMessage = nil
                let command = state.command
                let service = evolutionCommandService
                return .run { send in
                    do {
                        let output = try await service.executeCommand(command)
                        await send(.testFinished(.success(output)))
                    } catch {
                        await send(.testFinished(.failure(TestFailure(message: Self.message(for: error)))))
                    }
                }

            case let .testFinished(.success(output)):
                state.isTesting = false
                state.command.debugStatus = .success
                state.lastOutput = output
                state.errorMessage = nil
                return .none

            case let .testFinished(.failure(failure)):
                state.isTesting = false
                state.command.debugStatus = .failed
                state.lastOutput = nil
                state.errorMessage = failure.message
                return .none
            }
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? EvolutionError, error == .noCommand {
            return "The script is empty.".localized()
        }
        // The shared runner reports only that the script failed; the OSA
        // error itself goes to the shell log.
        return "The script failed. Check its syntax and the permissions it needs.".localized()
    }
}

extension EvolutionCommandEditingReducer.State {
    mutating func resetTestResult() {
        command.debugStatus = .unknow
        lastOutput = nil
        errorMessage = nil
    }
}
