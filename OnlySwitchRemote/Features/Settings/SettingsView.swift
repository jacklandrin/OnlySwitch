import ComposableArchitecture
import RemoteCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        List {
            if store.selectedMacID != nil {
                selectedOrderSection
                layoutSaveErrorSection
                controlsSection(title: "Built-ins", kind: .builtIn)
                controlsSection(title: "Shortcuts", kind: .shortcut)
                controlsSection(title: "Evolutions", kind: .evolution)
            }
        }
        .navigationTitle("Configure Controls")
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.foregroundChanged(false)) }
    }

    @ViewBuilder
    private var selectedOrderSection: some View {
        let ids = store.orderedVisibleSelectedControlIDs
        Section("On Dashboard") {
            if ids.isEmpty {
                Text("Add controls below to show them on your dashboard.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ids, id: \.self) { id in
                    if let descriptor = store.catalog[id: id] {
                        ControlSelectionRow(
                            descriptor: descriptor,
                            isSelected: true,
                            showsReorderHandle: true,
                            selectionChanged: { store.send(.toggleControl(descriptor.id, $0)) }
                        )
                    }
                }
                .onMove { store.send(.move($0, $1)) }
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    @ViewBuilder
    private var layoutSaveErrorSection: some View {
        if let macID = store.selectedMacID, store.layoutSaveIssueMacIDs.contains(macID) {
            Section {
                Button("Retry Saving Layout") { store.send(.retryLayoutSave(macID)) }
                    .disabled(store.layoutSaveInFlight.contains(macID))
            } footer: {
                Text("The dashboard layout wasn’t saved. Your latest choices are still available to retry.")
            }
        }
    }

    @ViewBuilder
    private func controlsSection(title: LocalizedStringKey, kind: RemoteControlID.Kind) -> some View {
        let controls = store.catalog.filter {
            $0.id.kind == kind && store.selectedControlIDs.contains($0.id) == false
        }
        if controls.isEmpty == false {
            Section(title) {
                ForEach(controls) { descriptor in
                    ControlSelectionRow(
                        descriptor: descriptor,
                        isSelected: store.selectedControlIDs.contains(descriptor.id),
                        showsReorderHandle: false,
                        selectionChanged: { store.send(.toggleControl(descriptor.id, $0)) }
                    )
                }
            }
        }
    }
}
