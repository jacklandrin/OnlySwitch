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
    struct State: Equatable {
        var evolutionList: IdentifiedArrayOf<EvolutionItem> = []
        var selectID: UUID?
        var editorViewActive = false
        var editorState = EvolutionEditorReducer.State()
        var showError = false
        var testNumber = 0
    }
    
    enum Action: Equatable {
        case refresh
        case loadList(TaskResult<[EvolutionItem]>)
        case select(UUID)
        case toggleItem(UUID)
        case remove
        case editorView(Bool)
        case editorState(EvolutionEditorReducer.Action)
        case editorItem(EvolutionItem?)
        case errorControl(Bool)
    }

    @Dependency(\.evolutionListService) var evolutionListService
    @Dependency(\.mainQueue) var mainQueue

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
                    state.evolutionList = IdentifiedArray(uniqueElements: list)
                    return .none

                case .loadList(.failure(_)):
                    state.showError = true
                    return .none

                case let .select(id):
                    state.selectID = id
                    return .none

                case let .toggleItem(id):
                    state.evolutionList[id: id]?.active.toggle()
                    return .none

                case .remove:
                    if let selectID = state.selectID {
                        state.evolutionList.remove(id: selectID)
                    }
                    return .none

                case let .editorView(active):
                    state.editorViewActive = active
                    return .none

                case let .editorState(action: .delegate(action)):
                    switch action {
                        case .goback:
                            state.editorViewActive = false
                    }
                    return .none

                case .editorState:
                    return .none

                case let .editorItem(item):
                    if let item {
                        state.editorState = EvolutionEditorReducer.State(evolution: item)
                    } else {
                        state.editorState = EvolutionEditorReducer.State()
                    }

                    return .none

                case let .errorControl(show):
                    state.showError = show
                    return .none
            }
        }
        
        Scope(state: \.editorState, action: /Action.editorState) {
            EvolutionEditorReducer()
        }

    }
}
