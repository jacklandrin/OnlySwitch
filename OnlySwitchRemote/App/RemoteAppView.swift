import ComposableArchitecture
import SwiftUI

struct RemoteAppView: View {
    @Bindable var store: StoreOf<RemoteAppFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let requiredStore = store.scope(
                state: \.requiredGlobalSettings,
                action: \.requiredGlobalSettings
            ) {
                NavigationStack { GlobalSettingsView(store: requiredStore) }
            } else {
                NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                    ZStack(alignment: .bottom) {
                        if store.selectedPage == .aphrodite, store.aphroditeAccess.canAccess == false {
                            RemotePaywallBackground()
                        } else {
                            DashboardBackground()
                        }

                        if store.selectedPage == .aphrodite, store.aphroditeAccess.canAccess, store.aphrodite.selectedApp != nil {
                            RemoteAphroditeView(store: store.scope(state: \.aphrodite, action: \.aphrodite))
                                .ignoresSafeArea(edges: .bottom)
                        } else {
                            TabView(selection: pageSelection) {
                                DashboardView(store: store.scope(state: \.dashboard, action: \.dashboard))
                                    .ignoresSafeArea(edges: .bottom)
                                    .tag(RemoteAppPage.controls)
                                RemoteSystemMonitorView(store: store.scope(state: \.systemMonitor, action: \.systemMonitor))
                                    .ignoresSafeArea(edges: .bottom)
                                    .tag(RemoteAppPage.systemMonitor)
                                RemoteCodexUsageView(store: store.scope(state: \.codexUsage, action: \.codexUsage))
                                    .ignoresSafeArea(edges: .bottom)
                                    .tag(RemoteAppPage.codexUsage)
                                RemoteClaudeUsageView(store: store.scope(state: \.claudeUsage, action: \.claudeUsage))
                                    .ignoresSafeArea(edges: .bottom)
                                    .tag(RemoteAppPage.claudeUsage)
                                RemoteAphroditeAccessView(
                                    accessStore: store.scope(state: \.aphroditeAccess, action: \.aphroditeAccess),
                                    toolsStore: store.scope(state: \.aphrodite, action: \.aphrodite)
                                )
                                    .ignoresSafeArea(edges: .bottom)
                                    .tag(RemoteAppPage.aphrodite)
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .ignoresSafeArea(edges: .bottom)
                        }

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
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Settings", systemImage: "gearshape") {
                                    store.send(.globalSettingsButtonTapped)
                                }
                                .labelStyle(.iconOnly)
                                .accessibilityHint("Opens app settings, help, and Mac pairing")
                            }
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                MacPickerView(
                                    style: .toolbar,
                                    macs: Array(store.pairedMacs),
                                    selectedMacID: store.selectedMacID,
                                    select: { store.send(.macSelected($0)) }
                                )
                                if store.selectedPage == .controls || store.selectedPage == .systemMonitor {
                                    Button(
                                        store.selectedPage == .systemMonitor
                                            ? "Configure System Monitor"
                                            : "Configure Controls",
                                        systemImage: "slider.horizontal.3"
                                    ) {
                                        if store.selectedPage == .systemMonitor {
                                            store.send(.systemMonitor(.delegate(.openConfiguration)))
                                        } else {
                                            store.send(.controlsConfigurationButtonTapped)
                                        }
                                    }
                                    .labelStyle(.iconOnly)
                                    .disabled(store.selectedMacID == nil)
                                    .accessibilityHint(
                                        store.selectedPage == .systemMonitor
                                            ? "Choose and reorder System Monitor widgets"
                                            : "Choose controls shown on the dashboard"
                                    )
                                }
                            }
                        }
                } destination: { destinationStore in
                    switch destinationStore.case {
                    case let .globalSettings(settingsStore):
                        GlobalSettingsView(store: settingsStore)
                    case let .controlsConfiguration(settingsStore):
                        SettingsView(store: settingsStore)
                    case let .monitorConfiguration(configurationStore):
                        RemoteSystemMonitorConfigurationView(store: configurationStore)
                    }
                }
            }
        }
        .sheet(item: $store.scope(state: \.$controlsConfiguration, action: \.controlsConfiguration)) { configurationStore in
            NavigationStack {
                SettingsView(store: configurationStore)
            }
            .modifier(ConfigurationSheetPresentation())
        }
        .sheet(item: $store.scope(state: \.$monitorConfiguration, action: \.monitorConfiguration)) { configurationStore in
            NavigationStack {
                RemoteSystemMonitorConfigurationView(store: configurationStore)
            }
            .modifier(ConfigurationSheetPresentation())
        }
        .sheet(item: $store.scope(state: \.$paywall, action: \.paywall)) { paywallStore in
            RemotePaywallView(store: paywallStore)
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
        .task { await store.send(.aphroditeAccess(.task)).finish() }
        .onChange(of: store.selectedPage) { _, page in
            if page == .aphrodite { store.send(.aphroditeAccess(.refresh)) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.send(.scenePhaseChanged(phase == .active))
            if phase == .active { store.send(.aphroditeAccess(.refresh)) }
        }
    }

    private var pageSelection: Binding<RemoteAppPage> {
        Binding(
            get: { store.selectedPage },
            set: { store.send(.pageSelected($0)) }
        )
    }
}

private struct ConfigurationSheetPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .presentationBackground {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: 32))
                }
        } else {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .presentationBackground(.regularMaterial)
        }
    }
}
