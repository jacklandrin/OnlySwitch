//
//  EvolutionView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import SwiftUI

@available(macOS 13.3, *)
struct EvolutionView: View {

    let store: StoreOf<EvolutionReducer>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                VStack {
                    ScrollView {
                        if viewStore.evolutionList.count == 0 {
                            Text("You can DIY switches or buttons here.")
                            Button("Refresh") {
                                viewStore.send(.refresh)
                            }
                        } else {
                            LazyVStack {
                                ForEach(viewStore.evolutionList) { item in
                                    evolutionItemView(item: item)
                                }
                            }

                            Spacer()
                        }

                    }
                    .padding(.top, 10)

                    HStack {
                        NavigationLink("+",
                                       destination:
                                        EvolutionEditorView(
                                            store: store.scope(
                                                state: \.editorState,
                                                action: EvolutionReducer.Action.editorState)

                                        )
                                            .task { @MainActor in
                                                viewStore.send(.editorItem(nil))
                                            },
                                       isActive: viewStore.binding(
                                        get: \.editorViewActive,
                                        send: {.editorView($0)}
                                       )
                        )

                        Button(action: {
                            viewStore.send(.remove)
                        }) {
                            Text("-")
                        }

                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 10)
                }
            }
            .toast(isPresenting: viewStore.binding(
                get: { $0.showError },
                send: { .errorControl($0) }
            ),
                   alert: {
                AlertToast(
                    displayMode: .alert,
                    type: .error(.red),
                    title: "load evolution list failed"
                )
            }
            )
            .task  {
                await viewStore.send(.refresh).finish()
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//                    viewStore.send(.refresh)
//                }
            }
        }
    }

    @ViewBuilder
    func evolutionItemView(item: EvolutionItem) -> some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            HStack {
                Toggle(
                    "",
                    isOn: viewStore.binding(
                        get: { _ in item.active },
                        send: .toggleItem(item.id)
                    )
                )
                Text(item.name)
                Spacer()
                NavigationLink(
                    destination:
                        EvolutionEditorView(
                            store: store.scope(
                                state: \.editorState,
                                action: EvolutionReducer.Action.editorState
                            )
                        )
                        .task { @MainActor in
                            viewStore.send(.editorItem(item))
                        }
                    , isActive: viewStore.binding(
                        get: \.editorViewActive,
                        send: {.editorView($0)}
                    )
                ) {
                    Text("Edit")
                }

            }
            .background(
                viewStore.selectID == item.id
                ? Color.accentColor
                : Color.gray.opacity(0.1)
            )
            .onTapGesture {
                viewStore.send(.select(item.id))
            }
            .padding(.horizontal, 20)
        }
    }
}

@available(macOS 13.3, *)
struct EvolutionView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionView(
            store: Store(initialState: EvolutionReducer.State(), reducer: EvolutionReducer()
                .dependency(\.evolutionListService, .previewValue)
            )
        )
    }
}
