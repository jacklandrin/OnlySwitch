//
//  EvolutionView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import SwiftUI

struct EvolutionView: View {
    let store: StoreOf<EvolutionReducer>

    var body: some View {
        WithPerceptionTracking {
            NavigationStack {
                HStack(spacing: 10) {
                    VStack {
                        HStack {
                            Text("To add or remove any Evolutions on list".localized())
                            Spacer()
                        }
                        Divider()
                        ScrollView(.vertical) {
                            if store.evolutionList.isEmpty {
                                Text("You can DIY switches or buttons here.".localized())
                                Button("Refresh".localized()) {
                                    store.send(.refresh)
                                }
                            } else {
                                VStack {
                                    ForEach(
                                        store.scope(
                                            state: \.evolutionList,
                                            action: \.editor
                                        )
                                    ) { itemStore in
                                        evolutionItemView(itemStore: itemStore)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .onTapGesture {
                            store.send(.select(nil))
                        }
                        .padding(.top, 10)

                        HStack {
                            Text("Pre-execution")
                            TextField(
                                "e.g: source ~/.zshrc",
                                text: Binding(
                                    get: { store.preExecution },
                                    set: { store.send(.setPreExecution($0)) }
                                    )
                            )
                        }

                        HStack {
                            Button {
                                store.send(.setNavigation(tag: .editor))
                            } label: {
                                Text("+")
                            }

                            Button(action: {
                                store.send(.remove)
                            }) {
                                Text("-")
                            }

                            Spacer()
                        }
                    }
                    .frame(minWidth: 370, idealWidth: 420, maxWidth: 420)
                    .padding(.bottom, 10)

                    EvolutionGalleryView(
                        store: store.scope(
                            state: \.galleryState,
                            action: \.galleryAction
                        )
                    )
                }
                .padding([.top, .leading], 10)
                .navigationDestination(
                    isPresented: Binding(
                        get: { store.destination?.tag == .editor },
                        set: { isPresented in
                            if !isPresented {
                                store.send(.setNavigation(tag: nil))
                            }
                        }
                    )
                ) {
                    if let editorStore = store.scope(
                        state: \.editorState,
                        action: \.editorAction
                    ) {
                        EvolutionEditorView(store: editorStore)
                    }
                }
            }
            .toast(isPresenting: Binding(
                get: { store.showError },
                set: { store.send(.errorControl($0)) }
            ),
                   alert: {
                AlertToast(
                    displayMode: .alert,
                    type: .error(.red),
                    title: "Load Evolution list failed".localized()
                )
            }
            )
            .task {
                await store.send(.refresh).finish()
            }
        }
    }

    @ViewBuilder
    func evolutionItemView(
        itemStore: StoreOf<EvolutionRowReducer>
    ) -> some View {
        WithPerceptionTracking {
            EvolutionRowView(store: itemStore)
            .background(
                store.selectID == itemStore.id
                ? Color.accentColor
                : Color.gray.opacity(0.1)
            )
            .onTapGesture {
                store.send(.select(itemStore.id))
            }
        }
    }
}

struct EvolutionView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionView(
            store: Store(
                initialState: EvolutionReducer.State()) {
                    EvolutionReducer()
                        .dependency(\.evolutionListService, .previewValue)
                }
        )
    }
}
