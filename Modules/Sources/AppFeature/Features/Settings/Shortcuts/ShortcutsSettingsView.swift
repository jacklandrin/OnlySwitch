//
//  ShortcutsSettingsView.swift
//  OnlySwitch
//

import AlertToast
import AppKit
import ComposableArchitecture
import SwiftUI

/// Settings › Shortcuts: "My Shortcuts" (menu selection and hotkeys) and "Gallery".
struct ShortcutsSettingsView: View {
    let store: StoreOf<ShortcutsSettingsReducer>

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch store.tab {
            case .mine:
                ShortcutsInstalledListView(store: store)
            case .gallery:
                ShortcutsGalleryView(store: store)
            }
        }
        .task { await store.send(.task).finish() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.send(.appBecameActive)
        }
        .toast(
            isPresenting: Binding(
                get: { store.message != nil },
                set: { if !$0 { store.send(.dismissMessage) } }
            ),
            alert: {
                AlertToast(
                    displayMode: .alert,
                    type: .error(.red),
                    title: "You can show up to 10 Shortcuts in the menu.".localized()
                )
            }
        )
    }

    private var header: some View {
        HStack {
            Picker(
                "Shortcuts".localized(),
                selection: Binding(
                    get: { store.tab },
                    set: { store.send(.tabChanged($0)) }
                )
            ) {
                Text("My Shortcuts".localized()).tag(ShortcutsSettingsReducer.Tab.mine)
                Text("Gallery".localized()).tag(ShortcutsSettingsReducer.Tab.gallery)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            if store.isLoadingShortcuts || store.isLoadingGallery {
                ProgressView().controlSize(.small)
            }
            Button("Refresh".localized(), systemImage: "arrow.clockwise") {
                store.send(.refresh)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Refresh".localized())
            .disabled(store.isLoadingShortcuts || store.isLoadingGallery)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    ShortcutsSettingsView(
        store: Store(initialState: ShortcutsSettingsReducer.State()) {
            ShortcutsSettingsReducer()
                .dependency(\.shortcutsSettingsClient, .previewValue)
        }
    )
    .frame(width: 760, height: 560)
}
