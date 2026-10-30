import ComposableArchitecture
import SwiftUI

/// The station area of the Radio settings page: saved stations and the radio-browser.info catalog.
public struct RadioStationsView: View {
    @Bindable var store: StoreOf<RadioStationsFeature>

    public init(store: StoreOf<RadioStationsFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $store.tab) {
                Text(favoritesTitle).tag(RadioStationsFeature.Tab.favorites)
                Text(RadioStrings.text("Radio Browse")).tag(RadioStationsFeature.Tab.browse)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 12)

            switch store.tab {
            case .favorites:
                RadioFavoritesView(store: store.scope(state: \.favorites, action: \.favorites)) {
                    store.send(.browseTapped)
                }
            case .browse:
                RadioBrowseView(store: store.scope(state: \.browse, action: \.browse), addingStationIDs: store.addingStationIDs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let message = store.message {
                RadioMessageBanner(message: message)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { store.send(.messageExpired) }
            }
        }
        .animation(.spring(duration: 0.3), value: store.message)
        .task { await store.send(.task).finish() }
        .sheet(item: $store.scope(state: \.favorites.editor, action: \.favorites.editor)) { editor in
            RadioStationEditorView(store: editor)
        }
        .alert($store.scope(state: \.favorites.alert, action: \.favorites.alert))
    }

    private var favoritesTitle: String {
        let title = RadioStrings.text("Radio Favorites")
        return store.favorites.favorites.isEmpty ? title : "\(title) (\(store.favorites.favorites.count))"
    }
}
