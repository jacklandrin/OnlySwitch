//
//  EvolutionRowView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/11.
//

import ComposableArchitecture
import SwiftUI

@available(macOS 13.3, *)
struct EvolutionRowView: View {

    let store: StoreOf<EvolutionRowReducer>
    @ObservedObject var viewStore: ViewStore<ViewState, EvolutionRowReducer.Action>

    struct ViewState: Equatable {
        let destinationTag: EvolutionRowReducer.DestinationState.Tag?

        init(state: EvolutionRowReducer.State) {
            self.destinationTag = state.destination?.tag
        }
    }

    init(store: StoreOf<EvolutionRowReducer>) {
        self.store = store
        self.viewStore = ViewStore(store.scope(state: ViewState.init(state:)))
    }

    var body: some View {
        WithViewStore(store) { viewStore in
            HStack {
                Toggle(
                    "",
                    isOn: viewStore.binding(
                        get: { _ in viewStore.evolution.active },
                        send: .toggle
                    )
                )
                Text(viewStore.evolution.name)
                Spacer()
                NavigationLink(
                    destination:
                        EvolutionEditorView(
                            store: store.scope(
                                state: \.editorState,
                                action: EvolutionRowReducer.Action.editorAction
                            )
                        ),
                    tag: EvolutionRowReducer.DestinationState.Tag.editor,
                    selection: viewStore.binding(
                        get: { _ in self.viewStore.destinationTag },
                        send: { EvolutionRowReducer.Action.setNavigation(tag:$0, state: viewStore.editorState) }
                    )
                ) {
                    Text("Edit")
                }

            }
        }
    }
}

@available(macOS 13.3, *)
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
