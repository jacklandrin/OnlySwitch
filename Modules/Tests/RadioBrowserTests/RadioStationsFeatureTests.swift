#if os(macOS)
import ComposableArchitecture
import Foundation
import Testing
@testable import RadioBrowser

@MainActor
struct RadioStationsFeatureTests {
    private func makeStore(_ library: FakeRadioLibrary, clock: TestClock<Duration> = TestClock(), state: RadioStationsFeature.State = .init()) -> TestStoreOf<RadioStationsFeature> {
        TestStore(initialState: state) { RadioStationsFeature() } withDependencies: {
            $0.radioLibraryClient = library.client
            $0.continuousClock = clock
        }
    }

    @Test func addingABrowserStationKeepsItsArtworkAndMarksItSaved() async {
        let library = FakeRadioLibrary(favorites: [RadioBrowserFixtures.favorite(1)])
        let station = RadioBrowserFixtures.station("s9", name: "Lofi", favicon: "https://example.com/lofi.png")
        var state = RadioStationsFeature.State()
        state.favorites.favorites = library.favorites
        let store = makeStore(library, state: state)
        store.exhaustivity = .off
        await store.send(.browse(.delegate(.addFavorite(station)))) {
            $0.addingStationIDs = ["s9"]
        }
        await store.receive(\.favoriteAdded) {
            $0.addingStationIDs = []
            $0.message = .added("Lofi")
        }
        await store.receive(\.favorites.favoritesLoaded)
        await store.receive(\.browse.favoriteURLsChanged)
        #expect(library.added.first?.1?.absoluteString == "https://example.com/lofi.png")
        #expect(library.added.first?.2 == "s9")
        #expect(store.state.browse.isFavorite(station))
    }

    @Test func addingADuplicateExplainsInsteadOfSaving() async {
        let station = RadioBrowserFixtures.station("s9", name: "Lofi")
        let existing = RadioBrowserFixtures.favorite(1, url: station.streamURL.absoluteString)
        let library = FakeRadioLibrary(favorites: [existing])
        var state = RadioStationsFeature.State()
        state.favorites.favorites = [existing]
        let store = makeStore(library, state: state)
        store.exhaustivity = .off
        await store.send(.browse(.delegate(.addFavorite(station)))) {
            $0.message = .alreadyInFavorites("Lofi")
        }
        #expect(library.added.isEmpty)
    }

    @Test func playbackUpdatesReachBothLists() async {
        let library = FakeRadioLibrary(favorites: [RadioBrowserFixtures.favorite(1)])
        let store = makeStore(library)
        store.exhaustivity = .off
        let task = await store.send(.task)
        await store.receive(\.favorites.favoritesLoaded)
        let status = RadioPlaybackStatus(currentID: library.favorites[0].id, isPlaying: true, previewingStationID: "s1")
        library.updates.continuation.yield(status)
        await store.receive(\.playbackChanged, status)
        #expect(store.state.favorites.playback == status)
        #expect(store.state.browse.previewingStationID == "s1")
        await task.cancel()
    }

    @Test func messagesDisappearOnTheirOwn() async {
        let clock = TestClock()
        let store = makeStore(FakeRadioLibrary(), clock: clock)
        await store.send(.favorites(.delegate(.notify(.exported)))) {
            $0.message = .exported
        }
        await clock.advance(by: RadioStationsFeature.messageDuration)
        await store.receive(\.messageExpired) { $0.message = nil }
    }

    @Test func emptyStateCanJumpToBrowse() async {
        let store = makeStore(FakeRadioLibrary())
        await store.send(.browseTapped) { $0.tab = .browse }
    }
}
#endif
