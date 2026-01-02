//
//  EvolutionRowView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/11.
//

import ComposableArchitecture
import SwiftUI
import KeyboardShortcuts
import Utilities

struct EvolutionRowView: View {

    @Perception.Bindable var store: StoreOf<EvolutionRowReducer>
    @ObservedObject var langManager = LanguageManager.sharedManager

    init(store: StoreOf<EvolutionRowReducer>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            HStack {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { store.evolution.active },
                        set: { _ in store.send(.toggle) }
                    )
                )
                Text(store.evolution.name)
                Spacer()
                Button {
                    store.send(.setNavigation(tag: .editor, state: store.editorState))
                } label: {
                    Text("Edit".localized())
                }
                .navigationDestination(
                    isPresented: Binding(
                        get: { store.destination?.tag == .editor },
                        set: { isPresented in
                            if !isPresented {
                                store.send(.setNavigation(tag: nil, state: store.editorState))
                            }
                        }
                    )
                ) {
                    EvolutionEditorView(
                        store: store.scope(
                            state: \.editorState,
                            action: \.editorAction
                        )
                    )
                }
                KeyboardShortcuts.Recorder(for: store.keyboardShortcutName)
                    .environment(\.locale, .init(identifier: langManager.currentLang))
                    .padding(.leading, 10)
            }
            .padding(2)
        }
    }
}

struct EvolutionRowView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionRowView(
            store: Store(
                initialState: EvolutionRowReducer.State(evolution: EvolutionItem())
            ) {
                EvolutionRowReducer()
            }
        )
    }
}
