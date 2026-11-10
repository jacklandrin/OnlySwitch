//
//  EvolutionEditorReducer+Generation.swift
//  OnlySwitch
//

import ComposableArchitecture
import Foundation
import OnlyAgent
import Switches

extension EvolutionEditorReducer {
    struct Generation: Equatable {
        var isAvailable: Bool
        var prompt = ""
        var isGenerating = false
        var error: EvolutionScriptGenerationError?
        var notes: String?
        /// A result waiting for the user to confirm replacing existing scripts.
        var pendingResult: PendingResult?
    }

    struct PendingResult: Equatable {
        let scripts: GeneratedEvolutionScripts
        let target: EvolutionScriptTarget
    }

    @CasePathable
    enum GenerationAction: Equatable {
        case promptChanged(String)
        case generateTapped
        case stopTapped
        case generated(Result<GeneratedEvolutionScripts, EvolutionScriptGenerationError>, EvolutionScriptTarget)
        case confirmReplace
        case cancelReplace
        case dismissError
        case openOnlyAgent
    }

    enum CancelID: Hashable {
        case generation
    }

    func reduceGeneration(_ state: inout State, _ action: GenerationAction) -> Effect<Action> {
        switch action {
        case let .promptChanged(prompt):
            state.generation.prompt = prompt
            return .none

        case .generateTapped:
            let description = state.generation.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard state.generation.isAvailable, !state.generation.isGenerating, !description.isEmpty else {
                return .none
            }
            state.generation.error = nil
            state.generation.notes = nil
            guard generationClient.isModelSelected() else {
                state.generation.error = .noModelSelected
                return .none
            }
            state.generation.isGenerating = true
            let target = Self.scriptTarget(for: state.evolution.controlType)
            let client = generationClient
            return .run { send in
                do {
                    let scripts = try await client.generate(description, target)
                    await send(.generation(.generated(.success(scripts), target)))
                } catch is CancellationError {
                    return
                } catch let error as EvolutionScriptGenerationError {
                    await send(.generation(.generated(.failure(error), target)))
                } catch {
                    await send(.generation(.generated(.failure(.failed(error.localizedDescription)), target)))
                }
            }
            .cancellable(id: CancelID.generation, cancelInFlight: true)

        case .stopTapped:
            state.generation.isGenerating = false
            return .cancel(id: CancelID.generation)

        case let .generated(.success(scripts), target):
            state.generation.isGenerating = false
            state.generation.notes = scripts.notes
            if Self.scriptTarget(for: state.evolution.controlType) == target, state.hasScripts {
                state.generation.pendingResult = PendingResult(scripts: scripts, target: target)
                return .none
            }
            Self.apply(scripts, target: target, to: &state)
            return .none

        case let .generated(.failure(error), _):
            state.generation.isGenerating = false
            state.generation.error = error
            return .none

        case .confirmReplace:
            guard let pending = state.generation.pendingResult else { return .none }
            state.generation.pendingResult = nil
            Self.apply(pending.scripts, target: pending.target, to: &state)
            return .none

        case .cancelReplace:
            state.generation.pendingResult = nil
            return .none

        case .dismissError:
            state.generation.error = nil
            return .none

        case .openOnlyAgent:
            let launcher = onlyAgentLauncher
            return .run { _ in await launcher.open() }
        }
    }

    static func scriptTarget(for controlType: ControlType) -> EvolutionScriptTarget {
        controlType == .Button ? .button : .switchControl
    }

    /// Writes generated scripts into the editor. Nothing is run: every script
    /// is marked untested and must pass ▶ Test before the Evolution can be saved.
    static func apply(_ scripts: GeneratedEvolutionScripts, target: EvolutionScriptTarget, to state: inout State) {
        if state.evolution.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let name = scripts.name {
            state.evolution.name = name
        }
        let isVisible = scriptTarget(for: state.evolution.controlType) == target
        var commands = isVisible ? state.commandStates : state.stashedCommandStates
        let assignments: [(CommandType, GeneratedScript?)] = switch target {
        case .switchControl: [(.on, scripts.turnOn), (.off, scripts.turnOff), (.status, scripts.status)]
        case .button: [(.single, scripts.button)]
        }
        for (type, script) in assignments {
            guard let script, var command = commands[id: type] else { continue }
            command.command.executeType = script.kind == .shell ? .shell : .applescript
            command.command.commandString = script.kind == .shell
                ? EvolutionShellQuoting.storedForm(ofShell: script.code)
                : script.code
            command.resetTestResult()
            if type == .status {
                command.command.trueCondition = scripts.statusOnOutput
            }
            commands[id: type] = command
        }
        if isVisible {
            state.commandStates = commands
        } else {
            state.stashedCommandStates = commands
        }
    }
}
