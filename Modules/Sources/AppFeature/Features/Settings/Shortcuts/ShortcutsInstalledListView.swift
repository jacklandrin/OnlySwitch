//
//  ShortcutsInstalledListView.swift
//  OnlySwitch
//

import ComposableArchitecture
import KeyboardShortcuts
import SwiftUI
import Utilities

/// Installed Shortcuts: menu visibility, a global hotkey, and Open in Shortcuts.
struct ShortcutsInstalledListView: View {
    let store: StoreOf<ShortcutsSettingsReducer>
    @ObservedObject private var langManager = LanguageManager.sharedManager

    var body: some View {
        if !store.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.shortcuts.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 0) {
                summary
                List {
                    ForEach(store.shortcuts) { shortcut in
                        row(shortcut)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Choose up to 10 Shortcuts to show in the OnlySwitch menu.".localized())
                .foregroundStyle(.secondary)
            Spacer()
            Text(
                String(
                    format: "%ld of %ld in the menu".localized(),
                    store.shownCount,
                    ShortcutsSettingsReducer.maximumShown
                )
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func row(_ shortcut: InstalledShortcut) -> some View {
        HStack(spacing: 10) {
            ShortcutIconView(pngData: store.icons[shortcut.name], size: 28, isActive: shortcut.isShown)
            Text(shortcut.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(shortcut.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            KeyboardShortcuts.Recorder(for: KeyboardShortcuts.Name(shortcut.name))
                .environment(\.locale, .init(identifier: langManager.currentLang))
            Button("Open in Shortcuts".localized(), systemImage: "arrow.up.forward.app") {
                store.send(.openInShortcuts(name: shortcut.name))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Open in Shortcuts".localized())
            Toggle(
                String(format: "Show %@ in the menu".localized(), shortcut.name),
                isOn: Binding(
                    get: { shortcut.isShown },
                    set: { store.send(.setShown(name: shortcut.name, isShown: $0)) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help("Show in the OnlySwitch menu".localized())
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Open in Shortcuts".localized(), systemImage: "arrow.up.forward.app") {
                store.send(.openInShortcuts(name: shortcut.name))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Shortcuts yet".localized(), systemImage: "square.stack.3d.up")
        } description: {
            Text("Create one in the Shortcuts app, or add one from the Gallery.".localized())
        } actions: {
            Button("Browse Gallery".localized(), systemImage: "square.grid.2x2") {
                store.send(.tabChanged(.gallery))
            }
            .evolutionProminentButtonStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
