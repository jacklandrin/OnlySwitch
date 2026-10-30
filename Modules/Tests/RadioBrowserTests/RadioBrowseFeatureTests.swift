#if os(macOS)
import ComposableArchitecture
import Foundation
import Testing
@testable import RadioBrowser

/// Records search queries and answers with a scripted page per call.
private actor SearchRecorder {
    var queries: [RadioBrowserQuery] = []
    var pages: [[RadioBrowserStation]]
    var clicks: [String] = []

    init(pages: [[RadioBrowserStation]]) {
        self.pages = pages
    }

    func search(_ query: RadioBrowserQuery) throws -> [RadioBrowserStation] {
        queries.append(query)
        guard !pages.isEmpty else { throw RadioBrowserError.unavailable }
        return pages.removeFirst()
    }

    func click(_ id: String) {
        clicks.append(id)
    }
}

@MainActor
struct RadioBrowseFeatureTests {
    private func page(_ range: ClosedRange<Int>) -> [RadioBrowserStation] {
        range.map { RadioBrowserFixtures.station("s\($0)") }
    }

    private func makeStore(
        _ recorder: SearchRecorder,
        library: FakeRadioLibrary = FakeRadioLibrary(),
        clock: TestClock<Duration> = TestClock(),
        state: RadioBrowseFeature.State = .init()
    ) -> TestStoreOf<RadioBrowseFeature> {
        TestStore(initialState: state) { RadioBrowseFeature() } withDependencies: {
            $0.radioBrowserClient = RadioBrowserClient(
                search: { try await recorder.search($0) },
                countries: { [RadioBrowserCountry(code: "DE", name: "Germany", stationCount: 3)] },
                tags: { [RadioBrowserTag(name: "jazz", stationCount: 9)] },
                registerClick: { await recorder.click($0) }
            )
            $0.radioLibraryClient = library.client
            $0.continuousClock = clock
        }
    }

    @Test func firstAppearanceLoadsPopularStationsAndFilters() async {
        let recorder = SearchRecorder(pages: [page(1...3)])
        let store = makeStore(recorder)
        store.exhaustivity = .off
        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()
        #expect(store.state.stations.map(\.id) == ["s1", "s2", "s3"])
        #expect(store.state.phase == .loaded)
        #expect(!store.state.canLoadMore, "A short page means there is nothing more")
        #expect(store.state.countries.map(\.code) == ["DE"])
        #expect(store.state.tags.map(\.name) == ["jazz"])

        await store.send(.task)
        await store.finish()
        #expect(await recorder.queries.count == 1, "Returning to the tab keeps the loaded results")
    }

    @Test func typingIsDebouncedIntoOneSearch() async {
        let clock = TestClock()
        let recorder = SearchRecorder(pages: [page(1...1)])
        let store = makeStore(recorder, clock: clock)
        store.exhaustivity = .off
        await store.send(.searchTextChanged("ja"))
        await clock.advance(by: .milliseconds(200))
        await store.send(.searchTextChanged("jazz"))
        await clock.advance(by: .milliseconds(399))
        #expect(await recorder.queries.isEmpty)
        await clock.advance(by: .milliseconds(1))
        await store.receive(\.performSearch)
        await store.receive(\.stationsResponse)
        #expect(await recorder.queries.map(\.text) == ["jazz"])
    }

    @Test func choosingACategoryResetsResultsAndSearchesImmediately() async {
        let recorder = SearchRecorder(pages: [page(1...2)])
        var state = RadioBrowseFeature.State()
        state.stations = IdentifiedArray(uniqueElements: page(10...12))
        state.query.offset = 40
        let store = makeStore(recorder, state: state)
        store.exhaustivity = .off
        await store.send(.categorySelected(.tag("jazz")))
        #expect(store.state.stations.isEmpty)
        #expect(store.state.phase == .loading)
        await store.receive(\.stationsResponse)
        let query = await recorder.queries.first
        #expect(query?.category == .tag("jazz"))
        #expect(query?.offset == 0)
        #expect(store.state.stations.map(\.id) == ["s1", "s2"])
    }

    @Test func loadMoreAppendsTheNextPage() async {
        let full = (1...RadioBrowserQuery.pageSize).map { RadioBrowserFixtures.station("a\($0)") }
        let recorder = SearchRecorder(pages: [full, page(1...2)])
        let store = makeStore(recorder)
        store.exhaustivity = .off
        await store.send(.performSearch)
        await store.receive(\.stationsResponse)
        #expect(store.state.canLoadMore)
        await store.send(.loadMore)
        await store.receive(\.stationsResponse)
        #expect(store.state.stations.count == RadioBrowserQuery.pageSize + 2)
        #expect(!store.state.canLoadMore)
        #expect(await recorder.queries.map(\.offset) == [0, RadioBrowserQuery.pageSize])
    }

    @Test func staleResponsesAreIgnored() async {
        let recorder = SearchRecorder(pages: [])
        var state = RadioBrowseFeature.State()
        state.generation = 5
        state.phase = .loading
        let store = makeStore(recorder, state: state)
        await store.send(.stationsResponse(generation: 4, appending: false, .success(page(1...2))))
        #expect(store.state.stations.isEmpty)
        #expect(store.state.phase == .loading)
    }

    @Test func failuresCanBeRetried() async {
        let recorder = SearchRecorder(pages: [])
        let store = makeStore(recorder)
        store.exhaustivity = .off
        await store.send(.performSearch)
        await store.receive(\.stationsResponse)
        #expect(store.state.phase == .failed(.unavailable))
        await recorder.setPages([page(1...1)])
        await store.send(.retry)
        await store.receive(\.stationsResponse)
        #expect(store.state.phase == .loaded)
    }

    @Test func returningToTheTabRetriesAFailedLoad() async {
        let recorder = SearchRecorder(pages: [])
        let store = makeStore(recorder)
        store.exhaustivity = .off
        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()
        #expect(store.state.phase == .failed(.unavailable))

        await recorder.setPages([page(1...1)])
        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()
        #expect(store.state.phase == .loaded)
        #expect(await recorder.queries.count == 2)
    }

    @Test func favoriteTapDelegatesUnlessAlreadySaved() async {
        let station = RadioBrowserFixtures.station("s1")
        var state = RadioBrowseFeature.State()
        state.stations = [station]
        let store = makeStore(SearchRecorder(pages: []), state: state)
        await store.send(.favoriteTapped(station))
        await store.receive(\.delegate.addFavorite)

        await store.send(.favoriteURLsChanged([station.streamURL.absoluteString + "/"])) {
            $0.favoriteURLs = [RadioStreamURL.normalized(station.streamURL.absoluteString)]
        }
        #expect(store.state.isFavorite(station))
        await store.send(.favoriteTapped(station))
    }

    @Test func previewTogglesAndCountsAClick() async {
        let station = RadioBrowserFixtures.station("s1")
        let library = FakeRadioLibrary()
        let recorder = SearchRecorder(pages: [])
        let store = makeStore(recorder, library: library)
        await store.send(.previewTapped(station)) { $0.previewingStationID = "s1" }
        await store.finish()
        #expect(library.previewed == ["s1"])
        #expect(await recorder.clicks == ["s1"])

        await store.send(.playbackChanged(RadioPlaybackStatus(isPlaying: true, previewingStationID: "s1")))
        await store.send(.previewTapped(station)) { $0.previewingStationID = nil }
        await store.finish()
        #expect(library.stopPreviews == 1)
    }

    @Test func leavingThePageStopsAPreview() async {
        let library = FakeRadioLibrary()
        var state = RadioBrowseFeature.State()
        state.previewingStationID = "s1"
        let store = makeStore(SearchRecorder(pages: []), library: library, state: state)
        await store.send(.disappeared) { $0.previewingStationID = nil }
        await store.finish()
        #expect(library.stopPreviews == 1)

        let idle = makeStore(SearchRecorder(pages: []), library: library)
        await idle.send(.disappeared)
        await idle.finish()
        #expect(library.stopPreviews == 1, "Nothing to stop when no preview is running")
    }
}

private extension SearchRecorder {
    func setPages(_ pages: [[RadioBrowserStation]]) {
        self.pages = pages
    }
}
#endif
