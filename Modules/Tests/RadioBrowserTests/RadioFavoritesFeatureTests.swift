#if os(macOS)
import ComposableArchitecture
import Foundation
import Testing
@testable import RadioBrowser

@MainActor
struct RadioFavoritesFeatureTests {
    private func makeStore(_ library: FakeRadioLibrary, state: RadioFavoritesFeature.State = .init()) -> TestStoreOf<RadioFavoritesFeature> {
        TestStore(initialState: state) { RadioFavoritesFeature() } withDependencies: {
            $0.radioLibraryClient = library.client
        }
    }

    @Test func reloadPublishesFavorites() async {
        let favorites = [RadioBrowserFixtures.favorite(1), RadioBrowserFixtures.favorite(2)]
        let store = makeStore(FakeRadioLibrary(favorites: favorites))
        await store.send(.reload)
        await store.receive(\.favoritesLoaded) { $0.favorites = favorites }
        await store.receive(\.delegate.favoritesChanged)
    }

    @Test func addingManuallySavesClosesTheSheetAndReloads() async {
        let library = FakeRadioLibrary(favorites: [RadioBrowserFixtures.favorite(1)])
        var state = RadioFavoritesFeature.State()
        state.favorites = library.favorites
        let store = makeStore(library, state: state)
        await store.send(.addTapped) {
            $0.editor = RadioStationEditorFeature.State(mode: .add, existing: state.favorites)
        }
        let valid = RadioFavoriteDraft.Valid(name: "New", streamURL: "https://new.example.com")
        await store.send(.editor(.presented(.delegate(.save(valid, editingID: nil)))))
        await store.receive(\.saveFinished) { $0.editor = nil }
        await store.receive(\.delegate.notify)
        await store.receive(\.reload)
        await store.receive(\.favoritesLoaded) { $0.favorites = library.favorites }
        await store.receive(\.delegate.favoritesChanged)
        #expect(library.added.map(\.0) == [valid])
    }

    @Test func editingUpdatesTheFavorite() async {
        let favorite = RadioBrowserFixtures.favorite(1)
        let library = FakeRadioLibrary(favorites: [favorite])
        var state = RadioFavoritesFeature.State()
        state.favorites = [favorite]
        let store = makeStore(library, state: state)
        store.exhaustivity = .off
        await store.send(.editTapped(favorite.id)) {
            $0.editor = RadioStationEditorFeature.State(mode: .edit(favorite), existing: [favorite])
        }
        let valid = RadioFavoriteDraft.Valid(name: "Renamed", streamURL: favorite.streamURL)
        await store.send(.editor(.presented(.delegate(.save(valid, editingID: favorite.id)))))
        await store.receive(\.saveFinished) { $0.editor = nil }
        await store.receive(\.favoritesLoaded)
        #expect(library.updated.map(\.0) == [favorite.id])
        #expect(store.state.favorites.first?.name == "Renamed")
    }

    @Test func aFailedSaveKeepsTheSheetOpen() async {
        let library = FakeRadioLibrary()
        library.failure = .storeUnavailable("disk full")
        var state = RadioFavoritesFeature.State()
        state.editor = RadioStationEditorFeature.State(mode: .add, existing: [])
        let store = makeStore(library, state: state)
        let valid = RadioFavoriteDraft.Valid(name: "New", streamURL: "https://new.example.com")
        await store.send(.editor(.presented(.delegate(.save(valid, editingID: nil)))))
        await store.receive(\.saveFinished)
        await store.receive(\.delegate.notify)
        #expect(store.state.editor != nil)
    }

    @Test func deletingAsksForConfirmationFirst() async {
        let favorites = [RadioBrowserFixtures.favorite(1), RadioBrowserFixtures.favorite(2)]
        let library = FakeRadioLibrary(favorites: favorites)
        var state = RadioFavoritesFeature.State()
        state.favorites = favorites
        let store = makeStore(library, state: state)
        store.exhaustivity = .off
        await store.send(.deleteTapped(favorites[0].id))
        #expect(store.state.alert != nil)
        #expect(library.deleted.isEmpty)
        await store.send(.alert(.presented(.confirmDelete(favorites[0].id)))) { $0.alert = nil }
        await store.receive(\.favoritesLoaded)
        #expect(library.deleted == [favorites[0].id])
        #expect(store.state.favorites == [favorites[1]])
    }

    @Test func theLastStationCannotBeDeleted() async {
        let favorite = RadioBrowserFixtures.favorite(1)
        let library = FakeRadioLibrary(favorites: [favorite])
        var state = RadioFavoritesFeature.State()
        state.favorites = [favorite]
        let store = makeStore(library, state: state)
        await store.send(.deleteTapped(favorite.id))
        await store.receive(\.delegate.notify)
        #expect(store.state.alert == nil)
        #expect(library.deleted.isEmpty)
    }

    @Test func playingTheCurrentStationToggles() async {
        let favorites = [RadioBrowserFixtures.favorite(1), RadioBrowserFixtures.favorite(2)]
        let library = FakeRadioLibrary(favorites: favorites)
        var state = RadioFavoritesFeature.State()
        state.favorites = favorites
        state.playback = RadioPlaybackStatus(currentID: favorites[0].id, isPlaying: true)
        let store = makeStore(library, state: state)
        await store.send(.playTapped(favorites[0].id))
        await store.send(.playTapped(favorites[1].id))
        await store.finish()
        #expect(library.toggles == 1)
        #expect(library.played == [favorites[1].id])
    }

    @Test func playingDuringAPreviewSelectsTheFavorite() async {
        let favorite = RadioBrowserFixtures.favorite(1)
        let library = FakeRadioLibrary(favorites: [favorite])
        var state = RadioFavoritesFeature.State()
        state.favorites = [favorite]
        state.playback = RadioPlaybackStatus(currentID: favorite.id, isPlaying: true, previewingStationID: "s1")
        let store = makeStore(library, state: state)
        await store.send(.playTapped(favorite.id))
        await store.finish()
        #expect(library.played == [favorite.id])
        #expect(library.toggles == 0)
    }

    @Test func filterMatchesNameAndHost() {
        var state = RadioFavoritesFeature.State()
        state.favorites = [
            RadioBrowserFixtures.favorite(1, name: "Jazz Lounge", url: "https://a.example.com"),
            RadioBrowserFixtures.favorite(2, name: "Rock", url: "https://jazzhost.example.com"),
            RadioBrowserFixtures.favorite(3, name: "News", url: "https://b.example.com")
        ]
        state.filterText = " jazz "
        #expect(state.visibleFavorites.map(\.name) == ["Jazz Lounge", "Rock"])
    }

    @Test func importReportsTheCountAndReloads() async {
        let library = FakeRadioLibrary(favorites: [RadioBrowserFixtures.favorite(1)])
        library.importResult = 3
        let store = makeStore(library)
        store.exhaustivity = .off
        await store.send(.importTapped)
        await store.receive(\.delegate.notify)
        await store.receive(\.favoritesLoaded)
    }

    @Test func cancelledImportIsSilent() async {
        let library = FakeRadioLibrary()
        library.importResult = nil
        let store = makeStore(library)
        await store.send(.importTapped)
        await store.finish()
    }

    @Test func copyingAURLUsesThePasteboard() async {
        let favorite = RadioBrowserFixtures.favorite(1)
        let library = FakeRadioLibrary(favorites: [favorite])
        var state = RadioFavoritesFeature.State()
        state.favorites = [favorite]
        let store = makeStore(library, state: state)
        await store.send(.copyURLTapped(favorite.id))
        await store.finish()
        #expect(library.copied == [favorite.streamURL])
    }
}
#endif
