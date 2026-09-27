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
                    ZStack(alignment: .bottom) {
                        DashboardBackground()

                        TabView(selection: pageSelection) {
                            DashboardView(store: store.scope(state: \.dashboard, action: \.dashboard))
                                .ignoresSafeArea(edges: .bottom)
                                .tag(RemoteAppPage.controls)
                            RemoteSystemMonitorView(store: store.scope(state: \.systemMonitor, action: \.systemMonitor))
                                .ignoresSafeArea(edges: .bottom)
                                .tag(RemoteAppPage.systemMonitor)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .ignoresSafeArea(edges: .bottom)

                        RemotePageTabBar(selection: pageSelection)
                            .padding(.bottom, 4)
                    }
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .overlay {
                            if store.isLoading {
                                ProgressView("Loading Macs")
                                    .padding()
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .toolbarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                MacPickerView(
                                    style: .toolbar,
                                    macs: Array(store.pairedMacs),
                                    selectedMacID: store.selectedMacID,
                                    select: { store.send(.macSelected($0)) }
                                )
                                Button("Settings", systemImage: "line.3.horizontal") {
                                    store.send(.settingsButtonTapped)
                                }
                                .labelStyle(.iconOnly)
                                .disabled(store.selectedPage == .systemMonitor && store.selectedMacID == nil)
                                .accessibilityLabel(
                                    store.selectedPage == .systemMonitor
                                        ? "System Monitor Configuration"
                                        : "Settings"
                                )
                                .accessibilityHint(
                                    store.selectedPage == .systemMonitor
                                        ? "Choose and reorder System Monitor widgets"
                                        : "Opens remote control settings"
                                )
                            }
                        }
                } destination: { destinationStore in
                    switch destinationStore.case {
                    case let .settings(settingsStore):
                        SettingsView(store: settingsStore)
                    case let .monitorConfiguration(configurationStore):
                        RemoteSystemMonitorConfigurationView(store: configurationStore)
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

    private var pageSelection: Binding<RemoteAppPage> {
        Binding(
            get: { store.selectedPage },
            set: { store.send(.pageSelected($0)) }
        )
    }
}
