//
//  ShortcutsGalleryView.swift
//  OnlySwitch
//

import ComposableArchitecture
import SwiftUI

/// Community Shortcuts, laid out like the Evolution gallery.
struct ShortcutsGalleryView: View {
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)]

    let store: StoreOf<ShortcutsSettingsReducer>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ready-made Shortcuts you can add to the Shortcuts app.".localized())
                    .foregroundStyle(.secondary)

                if store.galleryLoadFailed {
                    ContentUnavailableView {
                        Label("Couldn't load the gallery.".localized(), systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Retry".localized()) { store.send(.refresh) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else if store.gallery.isEmpty, store.isLoadingGallery {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.gallery) { item in
                            ShortcutsGalleryItemView(item: item, iconPNGData: item.isInstalled ? store.icons[item.name] : nil) {
                                store.send(.addFromGallery(item.id))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
