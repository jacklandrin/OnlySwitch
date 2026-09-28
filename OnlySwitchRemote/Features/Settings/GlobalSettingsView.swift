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

            Section {
                Button("Pair New Mac", systemImage: "plus.circle") {
                    store.send(.pairNewMacTapped)
                }

                NavigationLink {
                    HowToUseView()
                } label: {
                    Label("How to Use", systemImage: "questionmark.circle")
                }

                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
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
