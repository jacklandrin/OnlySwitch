import ComposableArchitecture
import RemoteCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        List {
            if store.isSetupRequired {
                Section {
                    ContentUnavailableView(
                        "Connect Your First Mac",
                        systemImage: "desktopcomputer.and.arrow.down",
                        description: Text("Enable iOS Remote Access in OnlySwitch on your Mac, then start pairing.")
                    )
                }
            }

            macsSection

            if store.selectedMacID != nil {
                selectedOrderSection
                controlsSection(title: "Built-ins", kind: .builtIn)
                controlsSection(title: "Shortcuts", kind: .shortcut)
                controlsSection(title: "Evolutions", kind: .evolution)
            }

            Section {
                Button("Pair Another Mac", systemImage: "plus.circle") {
                    store.send(.pairAnotherTapped)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarBackButtonHidden(store.isSetupRequired)
        .interactiveDismissDisabled(store.isSetupRequired)
        .toolbar {
            if store.orderedVisibleSelectedControlIDs.count > 1 { EditButton() }
        }
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.foregroundChanged(false)) }
        .sheet(item: $store.scope(state: \.pairing, action: \.pairing)) { pairingStore in
            PairingView(store: pairingStore)
        }
        .sheet(item: $store.scope(state: \.management, action: \.management)) { managementStore in
            NavigationStack { MacManagementView(store: managementStore) }
        }
    }

    private var macsSection: some View {
        Section("Macs") {
            if store.pairedMacs.isEmpty {
                Text("No paired Macs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.pairedMacs) { mac in
                    HStack(spacing: 12) {
                        Button {
                            store.send(.selectedMacChanged(mac.id))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mac.id == store.selectedMacID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(mac.id == store.selectedMacID ? Color.accentColor : .secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mac.displayName)
                                        .foregroundStyle(.primary)
                                    Text(status(for: mac).title)
                                        .font(.caption)
                                        .foregroundStyle(mac.requiresPairing ? .red : .secondary)
                                    if let date = mac.lastConnectedAt {
                                        Text("Last connected \(date, format: .relative(presentation: .named))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(mac.id == store.selectedMacID ? "Selected Mac: \(mac.displayName)" : "Select Mac: \(mac.displayName)"))

                        Button("Manage \(mac.displayName)", systemImage: "info.circle") {
                            store.send(.manageMac(mac.id))
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedOrderSection: some View {
        let ids = store.orderedVisibleSelectedControlIDs
        if ids.isEmpty == false {
            Section("Dashboard Tile Order") {
                ForEach(ids, id: \.self) { id in
                    if let descriptor = store.catalog[id: id] {
                        Label(descriptor.title, systemImage: "line.3.horizontal")
                    }
                }
                .onMove { store.send(.move($0, $1)) }
            }
        }
    }

    @ViewBuilder
    private func controlsSection(title: LocalizedStringKey, kind: RemoteControlID.Kind) -> some View {
        let controls = store.catalog.filter { $0.id.kind == kind }
        if controls.isEmpty == false {
            Section(title) {
                ForEach(controls) { descriptor in
                    ControlSelectionRow(
                        descriptor: descriptor,
                        isSelected: store.selectedControlIDs.contains(descriptor.id),
                        selectionChanged: { store.send(.toggleControl(descriptor.id, $0)) }
                    )
                }
                if let macID = store.selectedMacID, store.layoutSaveIssueMacIDs.contains(macID) {
                    Button("Retry Saving Layout") { store.send(.retryLayoutSave(macID)) }
                }
            }
        }
    }

    private func status(for mac: PairedMac) -> MacConnectionStatus {
        if mac.requiresPairing { return .needsPairing }
        return store.connectionStatuses[mac.id] ?? .unknown
    }
}
