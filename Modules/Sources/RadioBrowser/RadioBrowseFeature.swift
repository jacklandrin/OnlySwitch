import ComposableArchitecture
import Foundation

/// Searching radio-browser.info and auditioning or saving its stations.
@Reducer
public struct RadioBrowseFeature {
    public enum Phase: Equatable, Sendable {
        case idle, loading, loaded
        case failed(RadioBrowserError)
    }

    @ObservableState
    public struct State: Equatable {
        public var query = RadioBrowserQuery()
        public var stations: IdentifiedArrayOf<RadioBrowserStation> = []
        public var phase: Phase = .idle
        public var isLoadingMore = false
        public var canLoadMore = false
        public var countries: [RadioBrowserCountry] = []
        public var tags: [RadioBrowserTag] = []
        /// Normalized stream URLs of the user's favorites.
        public var favoriteURLs: Set<String> = []
        public var previewingStationID: String?
        public var generation = 0
        public var hasLoaded = false

        public init() {}

        public func isFavorite(_ station: RadioBrowserStation) -> Bool {
            favoriteURLs.contains(RadioStreamURL.normalized(station.streamURL.absoluteString))
        }
    }

    public enum Action: Sendable {
        case task
        case searchTextChanged(String)
        case categorySelected(RadioBrowserCategory)
        case performSearch
        case retry
        case loadMore
        case stationsResponse(generation: Int, appending: Bool, Result<[RadioBrowserStation], RadioBrowserError>)
        case filtersLoaded([RadioBrowserCountry], [RadioBrowserTag])
        case favoriteURLsChanged([String])
        case favoriteTapped(RadioBrowserStation)
        case previewTapped(RadioBrowserStation)
        case playbackChanged(RadioPlaybackStatus)
        case disappeared
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable {
            case addFavorite(RadioBrowserStation)
        }
    }

    private enum CancelID { case debounce, search }
    static let debounce = Duration.milliseconds(400)

    @Dependency(\.radioBrowserClient) private var browser
    @Dependency(\.radioLibraryClient) private var library
    @Dependency(\.continuousClock) private var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                if state.hasLoaded {
                    // Coming back to the tab after a failed load tries again; loaded results are kept.
                    guard case .failed = state.phase else { return .none }
                    return search(&state)
                }
                state.hasLoaded = true
                return .merge(
                    search(&state),
                    .run { [browser] send in
                        async let countries = (try? await browser.countries()) ?? []
                        async let tags = (try? await browser.tags()) ?? []
                        await send(.filtersLoaded(await countries, await tags))
                    }
                )

            case let .searchTextChanged(text):
                guard text != state.query.text else { return .none }
                state.query.text = text
                return .run { [clock] send in
                    try await clock.sleep(for: Self.debounce)
                    await send(.performSearch)
                }
                .cancellable(id: CancelID.debounce, cancelInFlight: true)

            case let .categorySelected(category):
                state.query.category = category
                return .merge(.cancel(id: CancelID.debounce), search(&state))

            case .performSearch, .retry:
                return search(&state)

            case .loadMore:
                guard state.phase == .loaded, state.canLoadMore, !state.isLoadingMore else { return .none }
                state.isLoadingMore = true
                state.query.offset += state.query.limit
                return fetch(state.query, generation: state.generation, appending: true)

            case let .stationsResponse(generation, appending, result):
                guard generation == state.generation else { return .none }
                switch result {
                case let .success(page):
                    if appending {
                        state.isLoadingMore = false
                        for station in page where state.stations[id: station.id] == nil {
                            state.stations.append(station)
                        }
                    } else {
                        state.stations = IdentifiedArray(page, uniquingIDsWith: { first, _ in first })
                        state.phase = .loaded
                    }
                    state.canLoadMore = page.count >= state.query.limit
                case let .failure(error):
                    if appending {
                        // Keep what is shown; the footer offers to try the same page again.
                        state.isLoadingMore = false
                        state.query.offset -= state.query.limit
                    } else {
                        state.phase = .failed(error)
                        state.canLoadMore = false
                    }
                }
                return .none

            case let .filtersLoaded(countries, tags):
                state.countries = countries
                state.tags = tags
                return .none

            case let .favoriteURLsChanged(urls):
                state.favoriteURLs = Set(urls.map(RadioStreamURL.normalized))
                return .none

            case let .favoriteTapped(station):
                guard !state.isFavorite(station) else { return .none }
                return .send(.delegate(.addFavorite(station)))

            case let .previewTapped(station):
                // Optimistic: the playback stream confirms or corrects this shortly.
                if state.previewingStationID == station.id {
                    state.previewingStationID = nil
                    return .run { [library] _ in await library.stopPreview() }
                }
                state.previewingStationID = station.id
                return .run { [library, browser] _ in
                    await library.preview(station)
                    await browser.registerClick(station.id)
                }

            case let .playbackChanged(status):
                state.previewingStationID = status.previewingStationID
                return .none

            case .disappeared:
                guard state.previewingStationID != nil else { return .none }
                state.previewingStationID = nil
                return .run { [library] _ in await library.stopPreview() }

            case .delegate:
                return .none
            }
        }
    }

    private func search(_ state: inout State) -> Effect<Action> {
        state.generation += 1
        state.query.offset = 0
        state.stations = []
        state.phase = .loading
        state.isLoadingMore = false
        state.canLoadMore = false
        return fetch(state.query, generation: state.generation, appending: false)
    }

    private func fetch(_ query: RadioBrowserQuery, generation: Int, appending: Bool) -> Effect<Action> {
        .run { [browser] send in
            do {
                let page = try await browser.search(query)
                await send(.stationsResponse(generation: generation, appending: appending, .success(page)))
            } catch is CancellationError {
                return
            } catch {
                await send(.stationsResponse(generation: generation, appending: appending, .failure(error as? RadioBrowserError ?? .unavailable)))
            }
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }
}
