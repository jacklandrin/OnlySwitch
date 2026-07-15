import ComposableArchitecture
import SwiftUI

struct RemoteAppView: View {
    @Bindable var store: StoreOf<RemoteAppFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            VStack(spacing: 16) {
                if store.isLoading {
                    ProgressView("Loading Macs")
                } else if store.selectedMacID == nil {
                    ContentUnavailableView(
                        "No Mac Selected",
                        systemImage: "desktopcomputer",
                        description: Text("Open Settings to pair with a Mac running OnlySwitch.")
                    )
                } else {
                    ContentUnavailableView(
                        "Dashboard",
                        systemImage: "switch.2",
                        description: Text("Choose remote controls in Settings.")
                    )
                }
            }
            .navigationTitle("OnlySwitch")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "line.3.horizontal") {
                        store.send(.settingsButtonTapped)
                    }
                    .disabled(store.requiresSetup || store.isLoading)
                    .accessibilityHint("Opens remote control settings")
                }
            }
        } destination: { destinationStore in
            switch destinationStore.case {
            case let .settings(settingsStore):
                SettingsView(store: settingsStore)
            }
        }
        .task {
            await store.send(.task).finish()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.send(.scenePhaseChanged(phase == .active))
        }
    }
}
