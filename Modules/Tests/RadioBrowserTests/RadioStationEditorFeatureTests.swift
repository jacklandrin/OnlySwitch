#if os(macOS)
import ComposableArchitecture
import Foundation
import Testing
@testable import RadioBrowser

@MainActor
struct RadioStationEditorFeatureTests {
    @Test func saveStaysDisabledUntilTheDraftIsValid() async {
        let store = TestStore(initialState: RadioStationEditorFeature.State(mode: .add, existing: [])) {
            RadioStationEditorFeature()
        }
        #expect(!store.state.canSave)
        #expect(store.state.visibleIssue == nil, "A blank form does not scold the user")

        await store.send(.binding(.set(\.streamURL, "radio"))) {
            $0.streamURL = "radio"
        }
        #expect(store.state.visibleIssue == .invalidURL)

        await store.send(.binding(.set(\.streamURL, "https://radio.example.com/live"))) {
            $0.streamURL = "https://radio.example.com/live"
        }
        #expect(store.state.visibleIssue == nil)
        #expect(!store.state.canSave, "A name is still required")

        await store.send(.binding(.set(\.name, "Radio"))) {
            $0.name = "Radio"
            $0.nameEdited = true
        }
        #expect(store.state.canSave)
    }

    @Test func clearingTheNameRevealsTheIssue() async {
        let store = TestStore(initialState: RadioStationEditorFeature.State(mode: .add, existing: [])) {
            RadioStationEditorFeature()
        }
        await store.send(.binding(.set(\.name, "A"))) {
            $0.name = "A"
            $0.nameEdited = true
        }
        await store.send(.binding(.set(\.name, " "))) { $0.name = " " }
        #expect(store.state.visibleIssue == .emptyName)
    }

    @Test func duplicateURLIsExplained() async {
        let existing = RadioBrowserFixtures.favorite(1)
        var state = RadioStationEditorFeature.State(mode: .add, existing: [existing])
        state.name = "Copy"
        state.streamURL = existing.streamURL + "/"
        #expect(state.visibleIssue == .duplicateURL)
        #expect(!state.canSave)
    }

    @Test func savingAValidDraftDelegatesTrimmedValues() async {
        var state = RadioStationEditorFeature.State(mode: .add, existing: [])
        state.name = " Radio "
        state.streamURL = "https://radio.example.com/live "
        let store = TestStore(initialState: state) { RadioStationEditorFeature() }
        await store.send(.saveTapped)
        await store.receive(\.delegate.save)
    }

    @Test func savingAnInvalidDraftDoesNothing() async {
        let store = TestStore(initialState: RadioStationEditorFeature.State(mode: .add, existing: [])) {
            RadioStationEditorFeature()
        }
        await store.send(.saveTapped) { $0.attemptedSave = true }
        #expect(store.state.visibleIssue == .emptyName)
    }

    @Test func editingPrefillsTheFavorite() {
        let favorite = RadioBrowserFixtures.favorite(3)
        let state = RadioStationEditorFeature.State(mode: .edit(favorite), existing: [favorite])
        #expect(state.name == favorite.name)
        #expect(state.streamURL == favorite.streamURL)
        #expect(state.canSave)
        #expect(state.editingID == favorite.id)
    }

    @Test func cancelDismisses() async {
        let dismissed = LockIsolated(false)
        let store = TestStore(initialState: RadioStationEditorFeature.State(mode: .add, existing: [])) {
            RadioStationEditorFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect { dismissed.setValue(true) }
        }
        await store.send(.cancelTapped)
        #expect(dismissed.value)
    }
}
#endif
