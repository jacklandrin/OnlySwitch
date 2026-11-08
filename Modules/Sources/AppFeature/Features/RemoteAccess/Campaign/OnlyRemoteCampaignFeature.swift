import ComposableArchitecture

@Reducer
struct OnlyRemoteCampaignFeature {
    @ObservableState
    struct State: Equatable {
        var hasChecked = false
        var isLoading = false
        var document: OnlyRemoteCampaignDocument?
        var isPresented = false
    }

    enum Action: Equatable {
        case launch
        case campaignLoaded(OnlyRemoteCampaignDocument?)
        case pageLoaded(String)
        case pageFailed(String)
        case dismissTapped
        case showQRCodeTapped
    }

    var forcePresentation = false

    private enum CancelID { case loading }
    @Dependency(\.onlyRemoteCampaign) var campaign

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .launch:
                guard !state.hasChecked, !state.isLoading, state.document == nil, !state.isPresented else { return .none }
                state.hasChecked = true
                state.isLoading = true
                let forcePresentation = forcePresentation
                return .run { send in
                    do {
                        let manifest = try await campaign.fetchLatest()
                        guard manifest.isValid else {
                            await send(.campaignLoaded(nil))
                            return
                        }
                        if !forcePresentation, let acknowledged = campaign.acknowledgedVersion(),
                           OnlyRemoteCampaignManifest(date: acknowledged, file: acknowledged + ".html").isValid,
                           acknowledged >= manifest.date {
                            await send(.campaignLoaded(nil))
                            return
                        }
                        let html = try await campaign.fetchHTML(manifest)
                        try Task.checkCancellation()
                        await send(.campaignLoaded(.init(manifest: manifest, html: html)))
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.campaignLoaded(nil))
                    }
                }
                .cancellable(id: CancelID.loading)

            case let .campaignLoaded(document):
                guard state.isLoading else { return .none }
                state.isLoading = false
                state.document = document
                return .none

            case let .pageLoaded(date):
                guard let document = state.document, document.manifest.date == date,
                      !state.isPresented else { return .none }
                state.isPresented = true
                guard !forcePresentation else { return .none }
                return .run { _ in await campaign.markAcknowledged(date) }

            case let .pageFailed(date):
                guard state.document?.manifest.date == date else { return .none }
                state.document = nil
                state.isPresented = false
                return .none

            case .dismissTapped:
                state.document = nil
                state.isPresented = false
                state.isLoading = false
                return .cancel(id: CancelID.loading)

            case .showQRCodeTapped:
                guard state.isPresented else { return .none }
                return .run { _ in await campaign.showQRCode() }
            }
        }
    }
}
