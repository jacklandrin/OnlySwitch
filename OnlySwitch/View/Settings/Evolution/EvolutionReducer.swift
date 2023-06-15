//
//  EvolutionReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import Combine
import ComposableArchitecture
import Foundation

struct EvolutionReducer: ReducerProtocol {
    enum DestinationState: Equatable {
        case editor(EvolutionEditorReducer.State)

        enum Tag: Int {
            case editor
        }

        var tag: Tag {
            switch self {
                case .editor:
                    return .editor
            }
        }
    }

    enum DestionationAction: Equatable {
        case gotoEditor(EvolutionEditorReducer.Action)
    }

    struct State: Equatable {
        var evolutionList: IdentifiedArrayOf<EvolutionRowReducer.State> = []
        var selectID: UUID?
        var editorState: EvolutionEditorReducer.State?
        var showError = false
        var destination: DestinationState?
    }
    
    enum Action: Equatable {
        case refresh
        case loadList(TaskResult<[EvolutionItem]>)
        case select(UUID)
        case toggleItem(UUID)
        case remove
        case setNavigation(tag: DestinationState.Tag?, state: EvolutionEditorReducer.State? = nil)
        case editor(id: UUID, action: EvolutionRowReducer.Action)
        case editorAction(EvolutionEditorReducer.Action)
        case errorControl(Bool)
    }

    @Dependency(\.evolutionListService) var evolutionListService

    var body: some ReducerProtocolOf<Self> {
        Reduce { state, action in
            switch action {
                case .refresh:
                    return .task {
                        return await .loadList(
                            TaskResult {
                                try await evolutionListService.loadEvolutionList()
                            }
                        )
                    }

                case let .loadList(.success(list)):
                    state.evolutionList = IdentifiedArray(
                        uniqueElements: list.compactMap {
                            EvolutionRowReducer.State(evolution: $0)
                        }
                    )
                    return .none

                case .loadList(.failure(_)):
                    state.showError = true
                    return .none

                case let .select(id):
                    state.selectID = id
                    return .none

                case let .toggleItem(id):
                    state.evolutionList[id: id]?.evolution.active.toggle()
                    return .none

                case .remove:
                    return .run { [state = state] send in
                        if let selectID = state.selectID {
                            try await evolutionListService.removeItem(selectID)
                            await send(.refresh)
                        }
                    }

                case let .setNavigation(tag: .editor, state: editorState):
                    if let editorState {
                        state.destination = .editor(editorState)
                    } else {
                        state.editorState = EvolutionEditorReducer.State()
                        state.destination = .editor(state.editorState ?? .init())
                    }

                    return .none

                case .setNavigation(tag: .none, state: _):
                    state.destination = nil
                    return .none

                case let .editorAction(.delegate(action)):
                    switch action {
                        case .goback:
                            state.destination = nil
                    }
                    return .send(.refresh)

                case .editorAction:
                    return .none

                case let .errorControl(show):
                    state.showError = show
                    return .none

                case .editor:
                    return .none
            }
        }
        .ifLet(\.editorState, action: /Action.editorAction) {
            EvolutionEditorReducer()
        }
        .forEach(\.evolutionList, action: /Action.editor(id:action:)) {
            EvolutionRowReducer()
        }
    }
}
