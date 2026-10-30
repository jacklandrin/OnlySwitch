import ComposableArchitecture
import Foundation

/// The Radio settings page: saved stations plus the radio-browser.info catalog.
@Reducer
public struct RadioStationsFeature {
    public enum Tab: String, CaseIterable, Equatable, Sendable {
        case favorites, browse
    }

    @ObservableState
    public struct State: Equatable {
        public var tab: Tab = .favorites
        public var favorites = RadioFavoritesFeature.State()
        public var browse = RadioBrowseFeature.State()
        public var message: RadioMessage?
        /// Browser stations currently being saved, so their buttons can show progress.
        public var addingStationIDs: Set<String> = []

        public init() {}
    }

    public enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case task
        case browseTapped
        case playbackChanged(RadioPlaybackStatus)
        case favoriteAdded(stationID: String, Result<RadioMessage, RadioLibraryError>)
        case messageExpired
        case favorites(RadioFavoritesFeature.Action)
        case browse(RadioBrowseFeature.Action)
    }

    private enum CancelID { case message }
    public static let messageDuration = Duration.seconds(3)

    @Dependency(\.radioLibraryClient) private var library
    @Dependency(\.continuousClock) private var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Scope(state: \.favorites, action: \.favorites) { RadioFavoritesFeature() }
        Scope(state: \.browse, action: \.browse) { RadioBrowseFeature() }
        Reduce { state, action in
            switch action {
            case .task:
                // Lives as long as the hosting view's `.task`, which cancels it on disappearance.
                return .merge(
                    .send(.favorites(.reload)),
                    .run { [library] send in
                        await send(.playbackChanged(await library.playbackStatus()))
                        for await status in library.playbackUpdates() {
                            await send(.playbackChanged(status))
                        }
                    }
                )

            case .browseTapped:
                state.tab = .browse
                return .none

            case let .playbackChanged(status):
                state.favorites.playback = status
                state.browse.previewingStationID = status.previewingStationID
                return .none

            case let .favorites(.delegate(.favoritesChanged(favorites))):
                return .send(.browse(.favoriteURLsChanged(favorites.map(\.streamURL))))

            case let .favorites(.delegate(.notify(message))):
                return show(message, in: &state)

            case let .browse(.delegate(.addFavorite(station))):
                guard !state.addingStationIDs.contains(station.id) else { return .none }
                let draft = RadioFavoriteDraft(name: station.name, streamURL: station.streamURL.absoluteString)
                switch draft.validate(existing: state.favorites.favorites, editingID: nil) {
                case .failure(.duplicateURL):
                    return show(.alreadyInFavorites(station.name), in: &state)
                case let .failure(issue):
                    return show(.failure(issue.text), in: &state)
                case let .success(valid):
                    state.addingStationIDs.insert(station.id)
                    return .run { [library] send in
                        do {
                            _ = try await library.add(valid, station.favicon, station.id)
                            await send(.favoriteAdded(stationID: station.id, .success(.added(valid.name))))
                        } catch {
                            await send(.favoriteAdded(stationID: station.id, .failure(RadioLibraryError(error))))
                        }
                    }
                }

            case let .favoriteAdded(stationID, result):
                state.addingStationIDs.remove(stationID)
                switch result {
                case let .success(message):
                    return .merge(show(message, in: &state), .send(.favorites(.reload)))
                case let .failure(error):
                    return show(error.message, in: &state)
                }

            case .messageExpired:
                state.message = nil
                return .none

            case .binding, .favorites, .browse:
                return .none
            }
        }
    }

    private func show(_ message: RadioMessage, in state: inout State) -> Effect<Action> {
        state.message = message
        return .run { [clock] send in
            try await clock.sleep(for: Self.messageDuration)
            await send(.messageExpired)
        }
        .cancellable(id: CancelID.message, cancelInFlight: true)
    }
}
