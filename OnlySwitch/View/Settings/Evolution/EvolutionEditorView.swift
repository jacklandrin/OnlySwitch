//
//  EvolutionEditorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import SwiftUI

@available(macOS 13.3, *)
struct EvolutionEditorView: View {

    let store: StoreOf<EvolutionEditorReducer>

    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            VStack {
                HStack {
                    Text("Name:")
                    TextField("",
                              text: viewStore.binding(
                                get: { $0.evolution.name },
                                send: { .changeName($0) }
                              )
                    )
                    Spacer()
                }

                Picker("",
                       selection: viewStore.binding(
                        get: { $0.evolution.controlType },
                        send: { .changeType($0) }
                       )
                ) {
                    Text("Switch").tag(ControlType.Switch)
                    Text("Button").tag(ControlType.Button)
                }
                .pickerStyle(.segmented)

                ScrollView {
                    if viewStore.evolution.controlType == .Switch {
                        switchEditorView
                    } else if viewStore.evolution.controlType == .Button {
                        buttonEditorView
                    }

                    EvolutionCommandEditingView(
                        store: Store(
                            initialState: viewStore.statusCommandState,
                            reducer: EvolutionCommandEditingReducer()
                                ._printChanges()
                        )
                    )
                }

                HStack {
                    Spacer()
                    Button(action: {
                        viewStore.send(.delegate(.goback))
                    }) {
                        Text("Save")
                    }
                }

            }
            .padding(10)
            .navigationTitle("Evolution Editor")
        }
    }

    @ViewBuilder
    var switchEditorView: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            VStack() {
                EvolutionCommandEditingView(
                    store: Store(
                        initialState: viewStore.onCommandState,
                        reducer: EvolutionCommandEditingReducer()
                            ._printChanges()
                    )
                )

                Spacer().frame(height: 20)

                EvolutionCommandEditingView(
                    store: Store(
                        initialState: viewStore.offCommandState,
                        reducer: EvolutionCommandEditingReducer()
                            ._printChanges()
                    )
                )
            }
        }
    }

    @ViewBuilder
    var buttonEditorView: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            VStack {
                EvolutionCommandEditingView(
                    store: Store(
                        initialState: viewStore.singleCommandState,
                        reducer: EvolutionCommandEditingReducer()
                            ._printChanges()
                    )
                )
                Spacer()
            }
        }
    }
}

@available(macOS 13.3, *)
struct EvolutionEditorView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionEditorView(store: Store(initialState: EvolutionEditorReducer.State(), reducer: EvolutionEditorReducer()))
    }
}
