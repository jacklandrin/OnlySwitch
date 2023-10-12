//
//  EvolutionGalleryView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import ComposableArchitecture
import SwiftUI

struct EvolutionGalleryView: View {

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    let store: StoreOf<EvolutionGalleryReducer>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack {
                HStack {
                    Text("Evolution Gallery".localized())
                    Spacer()
                    Button(action: {
                        viewStore.send(.refresh)
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("refresh".localized())
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEachStore(
                            store.scope(
                                state: \.galleryList,
                                action: EvolutionGalleryReducer.Action.itemAction(id: action:)
                            )
                        ) { itemStore in
                            EvolutionGalleryItemView(store: itemStore)
                        }
                    }
                    Spacer()
                }
            }
            .frame(width: 300)
            .padding(.horizontal, 10)
            .task {
                viewStore.send(.refresh)
            }
        }
    }
}

#Preview {
    EvolutionGalleryView(
        store: Store(initialState: EvolutionGalleryReducer.State()) {
            EvolutionGalleryReducer()
        }
    )
}
