//
//  EvolutionEditorReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import ComposableArchitecture
import Foundation
import OnlyAgent
import Switches

@Reducer
struct EvolutionEditorReducer {
    /// What still blocks saving, in the order it is shown to the user.
    enum Requirement: Equatable, Hashable {
        case name
        case script(CommandType)
        case test(CommandType)
        case statusOnOutput
    }

    struct SaveFailure: Error, Equatable {}

    @ObservableState
    struct State: Equatable, Identifiable {
        /// Working copy. Commands live in `commandStates` until `makeItem()`.
        var evolution: EvolutionItem
        /// The saved version (or the blank template for a new item).
        let original: EvolutionItem
        let isNew: Bool
        /// Commands of the visible control type.
        var commandStates: IdentifiedArrayOf<EvolutionCommandEditingReducer.State>
        /// Commands of the other control type, kept so toggling the type loses nothing.
        var stashedCommandStates: IdentifiedArrayOf<EvolutionCommandEditingReducer.State>
        var showIconPicker = false
        var isSaving = false
        var showSaveError = false
        var generation: Generation

        var id: UUID { evolution.id }

        init(evolution: EvolutionItem? = nil, generationAvailable: Bool = false) {
            let item = evolution ?? EvolutionItem()
            self.evolution = item
            self.original = item
            self.isNew = evolution == nil
            self.generation = Generation(isAvailable: generationAvailable)
            let switchStates: IdentifiedArrayOf<EvolutionCommandEditingReducer.State> = [
                .init(type: .on, command: item.onCommand),
                .init(type: .off, command: item.offCommand),
                .init(type: .status, command: item.statusCommand)
            ]
            let buttonStates: IdentifiedArrayOf<EvolutionCommandEditingReducer.State> = [
                .init(type: .single, command: item.singleCommand)
            ]
            if item.controlType == .Button {
                commandStates = buttonStates
                stashedCommandStates = switchStates
            } else {
                commandStates = switchStates
                stashedCommandStates = buttonStates
            }
        }
    }

    @CasePathable
    enum Action {
        case changeName(String)
        case toggleIconPicker(Bool)
        case selectIcon(String)
        case changeType(ControlType)
        case revert
        case save
        case saveFinished(Result<EvolutionItem, SaveFailure>)
        case dismissSaveError
        case commandAction(IdentifiedActionOf<EvolutionCommandEditingReducer>)
        case generation(GenerationAction)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case saved(EvolutionItem)
        }
    }

    @Dependency(\.evolutionCommandService) var evolutionCommandService
    @Dependency(\.evolutionScriptGenerationClient) var generationClient
    @Dependency(\.onlyAgentLauncher) var onlyAgentLauncher

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .changeName(name):
                state.evolution.name = name
                return .none

            case let .toggleIconPicker(isPresented):
                state.showIconPicker = isPresented
                return .none

            case let .selectIcon(name):
                state.evolution.iconName = name
                state.showIconPicker = false
                return .none

            case let .changeType(type):
                guard type != state.evolution.controlType, type == .Switch || type == .Button else {
                    return .none
                }
                state.evolution.controlType = type
                let visible = state.commandStates
                state.commandStates = state.stashedCommandStates
                state.stashedCommandStates = visible
                return .none

            case .revert:
                let generation = state.generation
                state = State(evolution: state.isNew ? nil : state.original, generationAvailable: generation.isAvailable)
                state.generation.prompt = generation.prompt
                return .none

            case .save:
                guard state.canSave else { return .none }
                state.isSaving = true
                let item = state.makeItem()
                let service = evolutionCommandService
                return .run { send in
                    do {
                        try await service.saveCommand(item)
                        await send(.saveFinished(.success(item)))
                    } catch {
                        await send(.saveFinished(.failure(SaveFailure())))
                    }
                }

            case let .saveFinished(.success(item)):
                state.isSaving = false
                return .send(.delegate(.saved(item)))

            case .saveFinished(.failure):
                state.isSaving = false
                state.showSaveError = true
                return .none

            case .dismissSaveError:
                state.showSaveError = false
                return .none

            case let .generation(action):
                return reduceGeneration(&state, action)

            case .commandAction, .delegate:
                return .none
            }
        }
        .forEach(\.commandStates, action: \.commandAction) {
            EvolutionCommandEditingReducer()
        }
    }
}
