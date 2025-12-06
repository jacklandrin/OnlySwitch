//
//  EvolutionView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import SwiftUI

@available(macOS 13.0, *)
struct EvolutionView: View {

    let store: StoreOf<EvolutionReducer>
    @ObservedObject var viewStore: ViewStore<ViewState, EvolutionReducer.Action>

    struct ViewState: Equatable {
        let destinationTag: EvolutionReducer.DestinationState.Tag?

        init(state: EvolutionReducer.State) {
            self.destinationTag = state.destination?.tag
        }
    }

    init(store: StoreOf<EvolutionReducer>) {
        self.store = store
        self.viewStore = ViewStore(store, observe: ViewState.init)
    }

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                HStack {
                    VStack {
                        HStack {
                            Text("To add or remove any Evolutions on list".localized())
                            Spacer()
                        }
                        Divider()
                        ScrollView(.vertical) {
                            if viewStore.evolutionList.isEmpty {
                                Text("You can DIY switches or buttons here.".localized())
                                Button("Refresh".localized()) {
                                    viewStore.send(.refresh)
                                }
                            } else {
                                VStack {
                                    ForEachStore(
                                        store.scope(
                                            state: \.evolutionList,
                                            action: \.editor
                                        )
                                    ) { itemStore in
                                        evolutionItemView(viewStore: viewStore, itemStore: itemStore)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .onTapGesture {
                            viewStore.send(.select(nil))
                        }
                        .padding(.top, 10)

                        HStack {
                            Text("Pre-execution")
                            TextField(
                                "e.g: source ~/.zshrc",
                                text: viewStore.binding(
                                        get: { $0.preExecution},
                                        send: { .setPreExecution($0) }
                                    )
                            )
                        }

                        HStack {
                            NavigationLink(
                                destination:
                                    IfLetStore(
                                        store.scope(
                                            state: \.editorState,
                                            action: EvolutionReducer.Action.editorAction)
                                    ) { editorStore in
                                        EvolutionEditorView(store: editorStore)
                                    },
                                tag: EvolutionReducer.DestinationState.Tag.editor,
                                selection: viewStore.binding(
                                    get: { _ in self.viewStore.destinationTag },
                                    send: { EvolutionReducer.Action.setNavigation(tag:$0) }
                                )
                            ) {
                                Text("+")
                            }

                            Button(action: {
                                viewStore.send(.remove)
                            }) {
                                Text("-")
                            }

                            Spacer()
                        }
                    }
                    .frame(width: 420)
                    .padding(.bottom, 10)

                    EvolutionGalleryView(
                        store: store.scope(
                            state: \.galleryState,
                            action: EvolutionReducer.Action.galleryAction
                        )
                    )
                }
                .padding([.top, .leading], 10)
            }
            .toast(isPresenting: viewStore.binding(
                get: { $0.showError },
                send: { .errorControl($0) }
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
                await viewStore.send(.refresh).finish()
            }
        }
    }

    @ViewBuilder
    func evolutionItemView(
        viewStore: ViewStore<EvolutionReducer.State, EvolutionReducer.Action>,
        itemStore: StoreOf<EvolutionRowReducer>
    ) -> some View {
        WithViewStore(itemStore, observe:{ $0 }) { itemViewStore in
            EvolutionRowView(store: itemStore)
            .background(
                viewStore.selectID == itemViewStore.id
                ? Color.accentColor
                : Color.gray.opacity(0.1)
            )
            .onTapGesture {
                viewStore.send(.select(itemViewStore.id))
            }
        }
    }
}

@available(macOS 13.0, *)
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
