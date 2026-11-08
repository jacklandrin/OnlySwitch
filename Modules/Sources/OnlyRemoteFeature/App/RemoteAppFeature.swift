import ComposableArchitecture
import Foundation

enum RemoteAppPage: Hashable, Sendable, CaseIterable {
    case controls
    case systemMonitor
    case soundMixer
    case brightness
    case screenshots
    case codexUsage
    case claudeUsage
    case aphrodite
}

@Reducer
struct RemoteAppFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        var requiredGlobalSettings: GlobalSettingsFeature.State?
        @Presents var controlsConfiguration: SettingsFeature.State?
        @Presents var monitorConfiguration: RemoteSystemMonitorConfigurationFeature.State?
        @Presents var paywall: RemotePaywallFeature.State?
        var pairedMacs: IdentifiedArrayOf<PairedMac> = []
        var selectedMacID: UUID?
        var dashboard = DashboardFeature.State()
        var selectedPage: RemoteAppPage = .controls
        var tabConfiguration: RemoteTabConfiguration
        var systemMonitor = RemoteSystemMonitorFeature.State()
        var soundMixer = RemoteSoundMixerFeature.State()
        var brightness = RemoteBrightnessFeature.State()
        var screenshots = RemoteScreenshotsFeature.State()
        var codexUsage = RemoteCodexUsageFeature.State()
        var claudeUsage = RemoteClaudeUsageFeature.State()
        var aphrodite = RemoteAphroditeFeature.State()
        var plusAccess = RemotePlusAccessFeature.State()
        var systemMonitorLayoutGeneration: UInt64 = 0
        var connectedMacIDs: Set<UUID> = []
        var activeSessionID: UUID?
        var pairAdoptionGeneration: UInt64 = 0
        var connectionEventRevision: UInt64 = 0
        var metadataRefreshGeneration: UInt64 = 0
        var hasCompletedInitialSetup: Bool
        var isLoading = false
        var loadGeneration: UInt64 = 0
        var isForegrounded = true
        var isKeepingScreenAwake = RemoteIdleTimerClient.preferenceSeed()
        var lifecycleGeneration: UInt64 = 0
        let persistenceWriterID: UUID
        var nextPersistenceSequence: UInt64 = 0
        var pendingPersistenceIntent: RemoteAppPersistenceIntent?
        var isPersisting = false
        var rootIssue: RootIssue?

        func showsPaywallBackground(for page: RemoteAppPage) -> Bool {
            page.requiresPlus && plusAccess.canAccess == false
        }

        init(
            hasCompletedInitialSetup: Bool,
            tabConfiguration: RemoteTabConfiguration = RemoteTabPreferencesClient.preferenceSeed(),
            persistenceWriterID: UUID = UUID()
        ) {
            self.hasCompletedInitialSetup = hasCompletedInitialSetup
            self.tabConfiguration = tabConfiguration
            self.persistenceWriterID = persistenceWriterID
            if hasCompletedInitialSetup == false {
                requiredGlobalSettings = .init(isSetupRequired: true, tabConfiguration: tabConfiguration)
            }
        }

        var requiresSetup: Bool { requiredGlobalSettings != nil }
    }

    struct LaunchResponse: Equatable, Sendable {
        let pairedMacs: [PairedMac]
        let selectedMacID: UUID?
        let connectionSnapshot: RemoteConnectionSnapshot

        init(
            pairedMacs: [PairedMac],
            selectedMacID: UUID?,
            connectionSnapshot: RemoteConnectionSnapshot = .init()
        ) {
            self.pairedMacs = pairedMacs
            self.selectedMacID = selectedMacID
            self.connectionSnapshot = connectionSnapshot
        }
    }

    enum LaunchResult: Equatable, Sendable {
        case success(LaunchResponse)
        case failure
    }

    enum PersistenceResult: Equatable, Sendable {
        case success
        case failure
    }

    enum RemoteSystemMonitorLayoutLoadResult: Equatable, Sendable {
        case success(MacSystemMonitorLayout?)
        case failure
    }

    enum RootIssue: Equatable, Sendable {
        case loadFailed
        case persistenceFailed

        var title: LocalizedStringResource {
            switch self {
            case .loadFailed: "Couldn’t Load Macs"
            case .persistenceFailed: "Changes Not Saved"
            }
        }

        var message: LocalizedStringResource {
            switch self {
            case .loadFailed: "OnlySwitch couldn’t load saved Macs. Your current screen was kept."
            case .persistenceFailed: "OnlySwitch couldn’t save the selected Mac and setup state."
            }
        }
    }

    enum Action: Equatable {
        case task
        case launchResponse(UInt64, LaunchResult)
        case connectionSnapshotLoaded(RemoteConnectionSnapshot)
        case connectionEvent(RemoteConnectionEvent)
        case pairAdoptionResponse(UInt64, UInt64, UUID, RemotePairAdoptionResult)
        case pairedMetadataRefreshed(UInt64, [PairedMac])
        case persistenceResponse(RemoteAppPersistenceIntent, PersistenceResult)
        case systemMonitorLayoutLoaded(UInt64, UUID, RemoteSystemMonitorLayoutLoadResult)
        case retryTapped
        case globalSettingsButtonTapped
        case controlsConfigurationButtonTapped
        case macSelected(UUID)
        case scenePhaseChanged(Bool)
        case lifecycleResponse(UInt64)
        case pageSelected(RemoteAppPage)
        case membershipTapped
        case dashboard(DashboardFeature.Action)
        case systemMonitor(RemoteSystemMonitorFeature.Action)
        case soundMixer(RemoteSoundMixerFeature.Action)
        case brightness(RemoteBrightnessFeature.Action)
        case screenshots(RemoteScreenshotsFeature.Action)
        case codexUsage(RemoteCodexUsageFeature.Action)
        case claudeUsage(RemoteClaudeUsageFeature.Action)
        case aphrodite(RemoteAphroditeFeature.Action)
        case plusAccess(RemotePlusAccessFeature.Action)
        case requiredGlobalSettings(GlobalSettingsFeature.Action)
        case controlsConfiguration(PresentationAction<SettingsFeature.Action>)
        case monitorConfiguration(PresentationAction<RemoteSystemMonitorConfigurationFeature.Action>)
        case paywall(PresentationAction<RemotePaywallFeature.Action>)
        case path(StackActionOf<Path>)
    }
    @Reducer
    enum Path {
        case globalSettings(GlobalSettingsFeature)
        case controlsConfiguration(SettingsFeature)
        case monitorConfiguration(RemoteSystemMonitorConfigurationFeature)
    }

    @Dependency(\.remoteConnection) var connection
    @Dependency(\.remotePersistence) var persistence
    @Dependency(\.remoteIdleTimer) var idleTimer
    enum CancelID { case load, lifecycle, connectionEvents, metadataRefresh }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            let before = ScreenshotsContext(state)
            let effect = core.reduce(into: &state, action: action)
            return .merge(effect, syncScreenshotsContext(from: before, after: action, state: state))
        }
    }

    @ReducerBuilder<State, Action>
    private var core: some ReducerOf<Self> {
        Scope(state: \.dashboard, action: \.dashboard) { DashboardFeature() }
        Scope(state: \.systemMonitor, action: \.systemMonitor) { RemoteSystemMonitorFeature() }
        Scope(state: \.soundMixer, action: \.soundMixer) { RemoteSoundMixerFeature() }
        Scope(state: \.brightness, action: \.brightness) { RemoteBrightnessFeature() }
        Scope(state: \.screenshots, action: \.screenshots) { RemoteScreenshotsFeature() }
        Scope(state: \.codexUsage, action: \.codexUsage) { RemoteCodexUsageFeature() }
        Scope(state: \.claudeUsage, action: \.claudeUsage) { RemoteClaudeUsageFeature() }
        Scope(state: \.aphrodite, action: \.aphrodite) { RemoteAphroditeFeature() }
        Scope(state: \.plusAccess, action: \.plusAccess) { RemotePlusAccessFeature() }
        Reduce { state, action in
            switch action {
            case .task:
                return reduceTask(&state)

            case let .launchResponse(generation, .failure):
                guard generation == state.loadGeneration else { return .none }
                state.isLoading = false
                state.rootIssue = .loadFailed
                return .none

            case let .launchResponse(generation, .success(response)):
                return reduceLaunchResponse(&state, generation: generation, response: response)

            case let .connectionSnapshotLoaded(snapshot):
                return reduceConnectionSnapshotLoaded(&state, snapshot: snapshot)

            case let .connectionEvent(event):
                return reduceConnectionEvent(&state, event: event)

            case let .pairAdoptionResponse(generation, eventRevision, id, result):
                return reducePairAdoptionResponse(&state, generation: generation, eventRevision: eventRevision, id: id, result: result)

            case let .pairedMetadataRefreshed(generation, macs):
                return reducePairedMetadataRefreshed(&state, generation: generation, macs: macs)

            case let .systemMonitorLayoutLoaded(generation, macID, result):
                return reduceSystemMonitorLayoutLoaded(&state, generation: generation, macID: macID, result: result)

            case let .persistenceResponse(intent, .success):
                guard state.pendingPersistenceIntent == intent else { return .none }
                state.pendingPersistenceIntent = nil
                state.isPersisting = false
                if state.rootIssue == .persistenceFailed { state.rootIssue = nil }
                return .none

            case let .persistenceResponse(intent, .failure):
                guard state.pendingPersistenceIntent == intent else { return .none }
                state.isPersisting = false
                state.rootIssue = .persistenceFailed
                return .none

            case .retryTapped:
                return reduceRetryTapped(&state)

            case .globalSettingsButtonTapped:
                return reduceGlobalSettingsButtonTapped(&state)

            case .controlsConfigurationButtonTapped:
                return reduceControlsConfigurationButtonTapped(&state)

            case let .macSelected(id):
                guard let mac = state.pairedMacs[id: id] else { return .none }
                return select(mac, state: &state)

            case let .scenePhaseChanged(foregrounded):
                return reduceScenePhaseChanged(&state, foregrounded: foregrounded)

            case let .lifecycleResponse(generation):
                guard generation == state.lifecycleGeneration else { return .none }
                return .none

            case let .pageSelected(page):
                return reducePageSelected(&state, page: page)

            case let .paywall(.presented(.restoreResponse(.success(entitlement)))),
                 let .paywall(.presented(.purchaseResponse(.success(.purchased(entitlement))))):
                return .send(.plusAccess(.entitlementUpdated(entitlement)))

            case .plusAccess(.entitlementResponse), .plusAccess(.entitlementUpdated),
                 .plusAccess(.entitlementExpired):
                return reducePlusAccessEntitlementChanged(&state)

            case .membershipTapped:
                state.paywall = .init()
                return .none

            case .dashboard(.delegate(.openSettings)):
                return .send(.controlsConfigurationButtonTapped)

            case .systemMonitor(.delegate(.openConfiguration)):
                guard let selectedMacID = state.selectedMacID else { return .none }
                let layout = state.systemMonitor.layout ?? .default(macID: selectedMacID)
                state.monitorConfiguration = .init(layout: layout)
                return .none

            case let .dashboard(.delegate(.selectedMac(mac))):
                return select(mac, state: &state)

            case .dashboard(.task):
                return reduceDashboardTask(&state)

            case let .requiredGlobalSettings(.delegate(.tabConfigurationChanged(configuration))),
                 let .path(.element(_, action: .globalSettings(.delegate(.tabConfigurationChanged(configuration))))):
                return reduceTabConfigurationChanged(&state, configuration: configuration)

            case let .requiredGlobalSettings(.delegate(.paired(mac))):
                state.requiredGlobalSettings = nil
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case .requiredGlobalSettings(.delegate(.openMembership)):
                state.paywall = .init()
                return .none

            case let .requiredGlobalSettings(.keepScreenAwakeToggled(isEnabled)):
                state.isKeepingScreenAwake = isEnabled
                let keepScreenAwake = state.isForegrounded && isEnabled
                return .run { [idleTimer] _ in
                    await idleTimer.setIdleTimerDisabled(keepScreenAwake)
                }

            case let .path(.element(_, action: .globalSettings(.delegate(.paired(mac))))):
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case .path(.element(_, action: .globalSettings(.delegate(.openMembership)))):
                state.paywall = .init()
                return .none

            case let .path(.element(_, action: .globalSettings(.keepScreenAwakeToggled(isEnabled)))):
                state.isKeepingScreenAwake = isEnabled
                let keepScreenAwake = state.isForegrounded && isEnabled
                return .run { [idleTimer] _ in
                    await idleTimer.setIdleTimerDisabled(keepScreenAwake)
                }

            case let .path(.element(_, action: .globalSettings(.delegate(.selectedMacChanged(mac))))):
                return select(mac, state: &state)

            case let .path(.element(_, action: .controlsConfiguration(.delegate(.layoutChanged(layout))))):
                guard state.dashboard.isActive else { return .none }
                return .send(.dashboard(.layoutChanged(layout)))

            case let .controlsConfiguration(.presented(.delegate(.layoutChanged(layout)))):
                guard state.dashboard.isActive else { return .none }
                return .send(.dashboard(.layoutChanged(layout)))

            case let .monitorConfiguration(.presented(.delegate(.layoutChanged(layout)))):
                guard state.selectedMacID == layout.macID else { return .none }
                state.systemMonitor.layout = layout
                return .none

            case let .path(.element(_, action: .globalSettings(.delegate(.macForgotten(id))))):
                state.pairedMacs.remove(id: id)
                state.connectedMacIDs.remove(id)
                invalidateMetadataRefresh(state: &state)
                syncSettingsState(&state)
                return .cancel(id: CancelID.metadataRefresh)

            case .path(.element(_, action: .globalSettings(.delegate(.allMacsRemoved)))):
                return reduceGlobalSettingsAllMacsRemoved(&state)

            // Kept for restoring older navigation stacks that may still emit these delegates.
            case let .path(.element(_, action: .controlsConfiguration(.delegate(.paired(mac))))):
                state.hasCompletedInitialSetup = true
                return paired(mac, state: &state)

            case let .path(.element(_, action: .controlsConfiguration(.delegate(.selectedMacChanged(mac))))):
                return select(mac, state: &state)

            case let .path(.element(_, action: .controlsConfiguration(.delegate(.macForgotten(id))))):
                state.pairedMacs.remove(id: id)
                state.connectedMacIDs.remove(id)
                invalidateMetadataRefresh(state: &state)
                syncSettingsState(&state)
                return .cancel(id: CancelID.metadataRefresh)

            case .path(.element(_, action: .controlsConfiguration(.delegate(.allMacsRemoved)))):
                return reduceControlsConfigurationAllMacsRemoved(&state)

            case let .path(.element(_, action: .monitorConfiguration(.delegate(.layoutChanged(layout))))):
                guard state.selectedMacID == layout.macID else { return .none }
                state.systemMonitor.layout = layout
                return .none

            case .dashboard, .systemMonitor, .soundMixer, .brightness, .screenshots, .codexUsage, .claudeUsage, .aphrodite, .plusAccess, .requiredGlobalSettings,
                 .controlsConfiguration, .monitorConfiguration, .paywall, .path:
                return .none
            }
        }
        .ifLet(\.requiredGlobalSettings, action: \.requiredGlobalSettings) { GlobalSettingsFeature() }
        .ifLet(\.$controlsConfiguration, action: \.controlsConfiguration) { SettingsFeature() }
        .ifLet(\.$monitorConfiguration, action: \.monitorConfiguration) { RemoteSystemMonitorConfigurationFeature() }
        .ifLet(\.$paywall, action: \.paywall) { RemotePaywallFeature() }
        .forEach(\.path, action: \.path)
    }
}

extension RemoteAppFeature.Path.State: Equatable {}
extension RemoteAppFeature.Path.Action: Equatable {}
