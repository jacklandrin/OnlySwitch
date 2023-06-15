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
        WithViewStore(store, observe: { $0 }) { viewStore in
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

                ScrollView(.vertical) {
                    VStack {
                        ForEachStore(
                            store.scope(
                                state: \.commandStates,
                                action: EvolutionEditorReducer.Action.commandAction(id:action:)
                            ),
                            content: { item in
                                EvolutionCommandEditingView(store: item)
                            }
                        )
                    }
                }

                HStack {
                    Spacer()
                    Button(action: {
                        viewStore.send(.save)
                    }) {
                        Text("Save")
                    }
                }

            }
            .padding(10)
            .navigationTitle("Evolution Editor")
            .onAppear{

            }
            .toast(isPresenting: viewStore.binding(
                get: { $0.showError },
                send: { .errorControl($0) }
            ),
                   alert: {
                AlertToast(
                    displayMode: .alert,
                    type: .error(.red),
                    title: "Save commands failed."
                )
            }
            )
        }
    }

//    @ViewBuilder
//    var switchEditorView: some View {
//        WithViewStore(self.store, observe: { $0 }) { viewStore in
//            VStack() {
//                EvolutionCommandEditingView(
//                    store: store.scope(
//                        state: \.onCommandState,
//                        action: EvolutionEditorReducer.Action.commandAction
//                    )
//                )
//
//                Spacer().frame(height: 20)
//
//                EvolutionCommandEditingView(
//                    store: store.scope(
//                        state: \.offCommandState,
//                        action: EvolutionEditorReducer.Action.commandAction
//                    )
//                )
//            }
//        }
//    }
//
//    @ViewBuilder
//    var buttonEditorView: some View {
//        WithViewStore(self.store, observe: { $0 }) { viewStore in
//            VStack {
//                EvolutionCommandEditingView(
//                    store: store.scope(
//                        state: \.singleCommandState,
//                        action: EvolutionEditorReducer.Action.commandAction
//                    )
//                )
//                Spacer()
//            }
//        }
//    }
}

@available(macOS 13.3, *)
struct EvolutionEditorView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionEditorView(store: Store(initialState: EvolutionEditorReducer.State(), reducer: EvolutionEditorReducer()))
    }
}
