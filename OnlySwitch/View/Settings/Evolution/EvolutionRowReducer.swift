//
//  EvolutionRowReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/11.
//

import ComposableArchitecture
import KeyboardShortcuts

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
        var keyboardShortcutName: KeyboardShortcuts.Name

        init(evolution: EvolutionItem) {
            self.evolution = evolution
            self.editorState = .init(evolution: evolution)
            self.id = evolution.id
            self.keyboardShortcutName = KeyboardShortcuts.Name(id.uuidString)

            if let evolutionIDs = UserDefaults.standard.array(forKey: UserDefaults.Key.evolutionIDs) as? [String] {
                let idString = id.uuidString
                self.evolution.active = evolutionIDs.contains(idString)
            } else {
                UserDefaults.standard.setValue([String](), forKey: UserDefaults.Key.evolutionIDs)
            }
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
                    guard let evolutionIDs = UserDefaults.standard.array(forKey: UserDefaults.Key.evolutionIDs) as? [String] else {
                        UserDefaults.standard.setValue([String](), forKey: UserDefaults.Key.evolutionIDs)
                        return .none
                    }
                    let idString = state.id.uuidString
                    var newEvolutionIDs = evolutionIDs
                    if state.evolution.active {
                        newEvolutionIDs.append(idString)
                    } else {
                        if let index = evolutionIDs.firstIndex(of: idString) {
                            newEvolutionIDs.remove(at: index)
                        }
                    }
                    UserDefaults.standard.setValue(newEvolutionIDs, forKey: UserDefaults.Key.evolutionIDs)
                    UserDefaults.standard.synchronize()
                    NotificationCenter.default.post(name: .changeSettings, object: nil)
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
