//
//  EvolutionView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import Defines
import SwiftUI

/// Settings › Evolution: "My Evolutions" (sidebar + inline editor) and "Gallery".
struct EvolutionView: View {
    let store: StoreOf<EvolutionReducer>

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch store.tab {
            case .mine:
                HStack(spacing: 0) {
                    EvolutionSidebarView(store: store)
                        .frame(width: 230)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .gallery:
                EvolutionGalleryView(store: store.scope(state: \.galleryState, action: \.galleryAction))
            }
        }
        .task { await store.send(.task).finish() }
        .onReceive(NotificationCenter.default.publisher(for: .changeSettings)) { _ in
            store.send(.refresh)
        }
        .confirmationDialog(
            String(format: "Delete “%@”?".localized(), store.pendingDeletion?.name ?? ""),
            isPresented: Binding(
                get: { store.pendingDeletion != nil },
                set: { if !$0 { store.send(.deleteCancelled) } }
            )
        ) {
            Button("Delete".localized(), role: .destructive) { store.send(.deleteConfirmed) }
            Button("Cancel".localized(), role: .cancel) { store.send(.deleteCancelled) }
        } message: {
            Text("This can't be undone.".localized())
        }
        .alert(
            "Discard unsaved changes?".localized(),
            isPresented: Binding(
                get: { store.pendingSelection != nil },
                set: { if !$0 { store.send(.discardChangesCancelled) } }
            )
        ) {
            Button("Discard".localized(), role: .destructive) { store.send(.discardChangesConfirmed) }
            Button("Keep Editing".localized(), role: .cancel) { store.send(.discardChangesCancelled) }
        }
        .toast(
            isPresenting: Binding(
                get: { store.showLoadError },
                set: { if !$0 { store.send(.dismissLoadError) } }
            ),
            alert: {
                AlertToast(displayMode: .alert, type: .error(.red), title: "Load Evolution list failed".localized())
            }
        )
    }

    private var header: some View {
        HStack {
            Picker(
                "Evolution".localized(),
                selection: Binding(
                    get: { store.tab },
                    set: { store.send(.tabChanged($0)) }
                )
            ) {
                Text("My Evolutions".localized()).tag(EvolutionReducer.Tab.mine)
                Text("Gallery".localized()).tag(EvolutionReducer.Tab.gallery)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            if store.isOnlyAgentAvailable {
                onlyAgentButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var onlyAgentButton: some View {
        if #available(macOS 26.0, *) {
            Button("Create with Only Agent".localized(), systemImage: "sparkles") {
                store.send(.openOnlyAgent)
            }
            .buttonStyle(.glass)
            .help("Describe what you want and let Only Agent write the script".localized())
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let editorStore = store.scope(state: \.detail, action: \.detail) {
            EvolutionEditorView(store: editorStore)
                .id(editorStore.id)
        } else if store.hasLoaded, store.evolutionList.isEmpty {
            EvolutionEmptyStateView(store: store)
        } else {
            ContentUnavailableView(
                "Select an Evolution".localized(),
                systemImage: "wand.and.rays",
                description: Text("Choose one on the left, or create a new one.".localized())
            )
        }
    }
}

#Preview {
    EvolutionView(
        store: Store(initialState: EvolutionReducer.State()) {
            EvolutionReducer()
                .dependency(\.evolutionListService, .previewValue)
                .dependency(\.onlyAgentLauncher, .previewValue)
        }
    )
    .frame(width: 860, height: 640)
}
