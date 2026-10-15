//
//  EvolutionGalleryView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import ComposableArchitecture
import SwiftUI

struct EvolutionGalleryView: View {

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 10)]

    let store: StoreOf<EvolutionGalleryReducer>

    var body: some View {
        WithPerceptionTracking {
            VStack {
                HStack {
                    Text("Evolution Gallery".localized())
                    Spacer()
                    Button(action: {
                        store.send(.refresh)
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("refresh".localized())
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(
                            store.scope(
                                state: \.galleryList,
                                action: \.itemAction
                            )
                        ) { itemStore in
                            EvolutionGalleryItemView(store: itemStore)
                        }
                    }
                    Spacer()
                }
            }
            .frame(minWidth: 210, maxWidth: .infinity)
            .padding(.horizontal, 10)
            .task {
                store.send(.refresh)
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
