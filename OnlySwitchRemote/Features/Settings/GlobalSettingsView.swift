import ComposableArchitecture
import SwiftUI

struct GlobalSettingsView: View {
    @Bindable var store: StoreOf<GlobalSettingsFeature>

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

            Section("Connection") {
                Button {
                    store.send(.pairNewMacTapped)
                } label: {
                    settingsRowLabel("Pair a Mac", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            Section("Paired Macs") {
                if store.pairedMacs.isEmpty {
                    Text("No paired Macs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.pairedMacs) { mac in
                        HStack(spacing: 12) {
                            Button {
                                store.send(.selectMac(mac.id))
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: mac.id == store.selectedMacID ? "checkmark.circle.fill" : statusSymbol(for: mac))
                                        .foregroundStyle(mac.id == store.selectedMacID ? Color.accentColor : statusTint(for: mac))
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

            Section("Display") {
                Toggle(isOn: Binding(
                    get: { store.isKeepingScreenAwake },
                    set: { store.send(.keepScreenAwakeToggled($0)) }
                )) {
                    settingsRowLabel("Keep Screen On", systemImage: "light.max")
                }
            }

            Section("Help & Feedback") {
                NavigationLink {
                    HowToUseView()
                } label: {
                    Label("How to Use", systemImage: "questionmark.circle")
                }

                Link(destination: Self.reviewURL) {
                    settingsRowLabel("Rate OnlyRemote", systemImage: "star")
                }
                .accessibilityHint("Opens the App Store review form")
            }

            Section("About") {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }

            Section("Recommended Apps") {
                Link(destination: URL(string: "https://apps.apple.com/us/app/id1590006394")!) {
                    HStack {
                        Image("QRCobot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(.rect(cornerRadius: 12))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading) {
                            Text("QRCobot")
                            Label("View on the App Store", systemImage: "arrow.up.forward.app")
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .foregroundStyle(Color.primary)
                .accessibilityLabel("Get QRCobot on the App Store")
                .accessibilityHint("Opens the App Store")

                Link(destination: URL(string: "https://apps.apple.com/us/app/onlybaby/id6758526534")!) {
                    HStack {
                        Image("OnlyBaby")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(.rect(cornerRadius: 12))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading) {
                            Text("OnlyBaby")
                            Label("View on the App Store", systemImage: "arrow.up.forward.app")
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .foregroundStyle(Color.primary)
                .accessibilityLabel("Get OnlyBaby on the App Store")
                .accessibilityHint("Opens the App Store")
            }
        }
        .navigationTitle("Settings")
        .navigationBarBackButtonHidden(store.isSetupRequired)
        .interactiveDismissDisabled(store.isSetupRequired)
        .sheet(item: $store.scope(state: \.pairing, action: \.pairing)) { pairingStore in
            PairingView(store: pairingStore)
        }
        .sheet(item: $store.scope(state: \.management, action: \.management)) { managementStore in
            NavigationStack { MacManagementView(store: managementStore) }
        }
    }

    private func settingsRowLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(Color.primary)
        }
    }

    private static let reviewURL = URL(string: "itms-apps://itunes.apple.com/app/id6793657946?action=write-review")!

    private func status(for mac: PairedMac) -> MacConnectionStatus {
        if mac.requiresPairing { return .needsPairing }
        return store.connectionStatuses[mac.id] ?? .unknown
    }

    private func statusSymbol(for mac: PairedMac) -> String {
        switch status(for: mac) {
        case .connected: "checkmark.circle.fill"
        case .connecting: "arrow.triangle.2.circlepath.circle"
        case .offline: "exclamationmark.circle"
        case .needsPairing: "link.badge.plus"
        case .unknown: "questionmark.circle"
        }
    }

    private func statusTint(for mac: PairedMac) -> Color {
        switch status(for: mac) {
        case .connected: .green
        case .connecting: .orange
        case .offline, .needsPairing: .red
        case .unknown: .secondary
        }
    }
}
