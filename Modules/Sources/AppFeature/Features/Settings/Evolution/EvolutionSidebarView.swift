//
//  EvolutionSidebarView.swift
//  OnlySwitch
//

import ComposableArchitecture
import SwiftUI

/// The list of saved Evolutions, + / −, and the Advanced pre-execution setting.
struct EvolutionSidebarView: View {
    let store: StoreOf<EvolutionReducer>
    @State private var showsAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            List(
                selection: Binding(
                    get: { store.detail?.isNew == true ? nil : store.selectedID },
                    set: { id in if let id { store.send(.rowTapped(id)) } }
                )
            ) {
                ForEach(store.scope(state: \.evolutionList, action: \.row)) { rowStore in
                    EvolutionRowView(store: rowStore)
                        .tag(rowStore.id)
                        .contextMenu {
                            Button("Delete…".localized(), systemImage: "trash", role: .destructive) {
                                store.send(.deleteTapped(rowStore.id))
                            }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onDeleteCommand {
                if let id = store.selectedID { store.send(.deleteTapped(id)) }
            }

            Divider()

            HStack(spacing: 4) {
                Button("New Evolution".localized(), systemImage: "plus") {
                    store.send(.newTapped)
                }
                .help("New Evolution".localized())
                Button("Delete…".localized(), systemImage: "minus") {
                    if let id = store.selectedID { store.send(.deleteTapped(id)) }
                }
                .help("Delete…".localized())
                .disabled(store.selectedID == nil || store.detail?.isNew == true)
                Spacer()
                Button("Advanced".localized(), systemImage: "gearshape") {
                    showsAdvanced.toggle()
                }
                .help("Advanced".localized())
                .popover(isPresented: $showsAdvanced, arrowEdge: .top) {
                    advanced
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        // A content-coloured column, so the list doesn't blend into the Settings sidebar beside it.
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pre-execution".localized())
                .font(.headline)
            TextField(
                "Pre-execution".localized(),
                text: Binding(
                    get: { store.preExecution },
                    set: { store.send(.setPreExecution($0)) }
                ),
                prompt: Text(verbatim: "source ~/.zshrc")
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .labelsHidden()
            Text("Runs before every Shell script, e.g. source ~/.zshrc to load your PATH.".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300)
    }
}
