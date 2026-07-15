import ComposableArchitecture
import SwiftUI

struct RemoteAppView: View {
    @Bindable var store: StoreOf<RemoteAppFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let requiredStore = store.scope(state: \.requiredSettings, action: \.requiredSettings) {
                NavigationStack { SettingsView(store: requiredStore) }
            } else {
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
                            .disabled(store.isLoading)
                            .accessibilityHint("Opens remote control settings")
                        }
                    }
                } destination: { destinationStore in
                    switch destinationStore.case {
                    case let .settings(settingsStore):
                        SettingsView(store: settingsStore)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let issue = store.rootIssue {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.headline)
                        Text(issue.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Retry") { store.send(.retryTapped) }
                        .buttonStyle(.bordered)
                        .disabled(store.isLoading || store.isPersisting)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
        .task { await store.send(.task).finish() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.send(.scenePhaseChanged(phase == .active))
        }
    }
}
