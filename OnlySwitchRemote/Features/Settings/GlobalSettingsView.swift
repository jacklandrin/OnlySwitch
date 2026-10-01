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
                    settingsRowLabel("Pair New Mac", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
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
}
