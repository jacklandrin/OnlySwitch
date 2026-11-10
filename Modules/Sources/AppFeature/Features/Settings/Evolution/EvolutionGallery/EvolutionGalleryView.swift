//
//  EvolutionGalleryView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import ComposableArchitecture
import SwiftUI

/// Ready-made Evolutions shared by the community.
struct EvolutionGalleryView: View {
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)]

    let store: StoreOf<EvolutionGalleryReducer>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ready-made Evolutions you can add and then edit.".localized())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Button("Refresh".localized(), systemImage: "arrow.clockwise") {
                        store.send(.refresh)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Refresh".localized())
                    .disabled(store.isLoading)
                }

                if store.loadFailed {
                    ContentUnavailableView {
                        Label("Couldn't load the gallery.".localized(), systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Retry".localized()) { store.send(.refresh) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.scope(state: \.galleryList, action: \.itemAction)) { itemStore in
                            EvolutionGalleryItemView(store: itemStore)
                        }
                    }
                }
            }
            .padding(16)
        }
        .task {
            if store.galleryList.isEmpty {
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
