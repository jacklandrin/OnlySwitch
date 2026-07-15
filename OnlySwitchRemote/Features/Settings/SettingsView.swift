import ComposableArchitecture
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

            if store.pairedMacs.isEmpty == false {
                Section("Paired Macs") {
                    ForEach(store.pairedMacs) { mac in
                        Label(mac.displayName, systemImage: "desktopcomputer")
                            .accessibilityLabel("\(mac.displayName), paired Mac")
                    }
                }
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
        .sheet(item: $store.scope(state: \.pairing, action: \.pairing)) { pairingStore in
            PairingView(store: pairingStore)
        }
    }
}
