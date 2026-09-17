import ComposableArchitecture

@Reducer
struct OnlyRemoteCampaignFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented = false
        var isOpeningRemoteAccessSettings = false
    }

    enum Action: Equatable {
        case launch(forcePresentation: Bool)
        case dismissTapped
        case downloadTapped
        case openRemoteAccessSettingsTapped
    }

    @Dependency(\.onlyRemoteCampaign) var campaign

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .launch(forcePresentation):
                state.isPresented = forcePresentation || campaign.acknowledgedVersion() != campaign.currentVersion()
                return .none

            case .dismissTapped:
                guard state.isPresented else { return .none }
                state.isPresented = false
                let version = campaign.currentVersion()
                return .run { _ in
                    await campaign.markAcknowledged(version)
                }

            case .downloadTapped:
                guard state.isPresented else { return .none }
                state.isPresented = false
                let version = campaign.currentVersion()
                return .run { _ in
                    await campaign.markAcknowledged(version)
                    await campaign.openAppStore()
                }

            case .openRemoteAccessSettingsTapped:
                guard state.isPresented else { return .none }
                state.isPresented = false
                // The window controller consults this synchronously while it closes,
                // keeping the app active until Settings has been brought forward.
                state.isOpeningRemoteAccessSettings = true
                let version = campaign.currentVersion()
                return .run { _ in
                    await campaign.markAcknowledged(version)
                    await campaign.openRemoteAccessSettings()
                }
            }
        }
    }
}
