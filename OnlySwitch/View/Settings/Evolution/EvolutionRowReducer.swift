//
//  EvolutionRowReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/11.
//

import ComposableArchitecture

struct EvolutionRowReducer: ReducerProtocol {
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

    struct State: Equatable, Identifiable {
        let id: UUID
        var evolution: EvolutionItem
        var editorState: EvolutionEditorReducer.State
        var destination: DestinationState?

        init(evolution: EvolutionItem) {
            self.evolution = evolution
            self.editorState = .init(evolution: evolution)
            self.id = evolution.id
        }
    }

    enum Action: Equatable {
        case toggle
        case setNavigation(tag: DestinationState.Tag?, state: EvolutionEditorReducer.State? = nil)
        case editorAction(EvolutionEditorReducer.Action)
    }

    var body: some ReducerProtocolOf<Self> {
        Reduce { state, action in
            switch action {
                case .toggle:
                    state.evolution.active.toggle()
                    return .none

                case let .setNavigation(tag: .editor, state: editorState):
                    if let editorState {
                        state.destination = .editor(editorState)
                    } else {
                        state.destination = nil
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
                    return .none

                case .editorAction:
                    return .none

            }
        }

        Scope(state: \.editorState, action: /Action.editorAction) {
            EvolutionEditorReducer()
        }
    }
}
