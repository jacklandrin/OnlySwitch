//
//  EvolutionEditorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import SwiftUI

@available(macOS 13.0, *)
struct EvolutionEditorView: View {

    let store: StoreOf<EvolutionEditorReducer>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack {
                HStack {
                    Text("Name:".localized())
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
                    Text("Switch".localized()).tag(ControlType.Switch)
                    Text("Button".localized()).tag(ControlType.Button)
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
                    Text("Can be saved after passing all tests".localized())
                    Button(action: {
                        viewStore.send(.save)
                    }) {
                        Text("Save".localized())
                    }
                }

            }
            .padding(10)
            .navigationTitle("Evolution Editor".localized())
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
                    title: "Save commands failed.".localized()
                )
            }
            )
        }
    }
}

@available(macOS 13.0, *)
struct EvolutionEditorView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionEditorView(store: Store(initialState: EvolutionEditorReducer.State(), reducer: EvolutionEditorReducer()))
    }
}
