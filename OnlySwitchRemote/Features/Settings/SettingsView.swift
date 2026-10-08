import ComposableArchitecture
import RemoteCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if store.selectedMacID != nil {
                layoutSaveErrorSection
                allControlsSection
            }
        }
        .navigationTitle("Configure Controls")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .accessibilityHint("Dismisses control configuration")
            }
        }
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.foregroundChanged(false)) }
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
    private var allControlsSection: some View {
        Section("Controls") {
            ForEach(store.orderedVisibleSelectedControlIDs, id: \.self) { id in
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

            ForEach(store.catalog.filter { store.selectedControlIDs.contains($0.id) == false }) { descriptor in
                ControlSelectionRow(
                    descriptor: descriptor,
                    isSelected: false,
                    showsReorderHandle: false,
                    selectionChanged: { store.send(.toggleControl(descriptor.id, $0)) }
                )
            }
        }
    }
}
