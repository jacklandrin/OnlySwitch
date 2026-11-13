import ComposableArchitecture
import Foundation
import Testing
@testable import WebBrowser

@MainActor
struct BrowserFeatureBrowsingTests {
    private func startedState(_ bookmarks: [BrowserBookmark], selected: UUID?) -> BrowserFeature.State {
        var state = BrowserFeature.State()
        state.hasStarted = true
        state.bookmarks = IdentifiedArray(uniqueElements: bookmarks)
        state.selectedID = selected
        return state
    }

    @Test func onAppearRestoresSelectionAndActivatesItOnce() async {
        let log = WebCommandLog()
        let (one, two) = (BrowserBookmark.fixture(1), BrowserBookmark.fixture(2))
        let store = TestStore(initialState: BrowserFeature.State()) { BrowserFeature() } withDependencies: {
            $0.browserStorage = log.storage(.loaded(.init(bookmarks: [one, two], selectedID: two.id)))
            $0.browserWebClient = log.client()
        }
        await store.send(.onAppear) {
            $0.hasStarted = true
            $0.bookmarks = [one, two]
            $0.selectedID = two.id
            $0.addressText = "https://site2.example"
        }
        await store.send(.onAppear)
        await store.finish()
        #expect(log.commands.value == ["activate 2"])
    }

    @Test func unknownSelectionFallsBackToFirst() async {
        let log = WebCommandLog()
        let one = BrowserBookmark.fixture(1)
        let store = TestStore(initialState: BrowserFeature.State()) { BrowserFeature() } withDependencies: {
            $0.browserStorage = log.storage(.loaded(.init(bookmarks: [one, one], selectedID: UUID())))
            $0.browserWebClient = log.client()
        }
        await store.send(.onAppear) {
            $0.hasStarted = true
            $0.bookmarks = [one]
            $0.selectedID = one.id
            $0.addressText = "https://site1.example"
        }
        await store.finish()
    }

    @Test func corruptedStorageIsFlaggedWithoutActivatingAnything() async {
        let log = WebCommandLog()
        let store = TestStore(initialState: BrowserFeature.State()) { BrowserFeature() } withDependencies: {
            $0.browserStorage = log.storage(.corrupted)
            $0.browserWebClient = log.client()
        }
        await store.send(.onAppear) {
            $0.hasStarted = true
            $0.storageCorrupted = true
        }
        await store.finish()
        #expect(log.commands.value.isEmpty)
    }

    @Test func navigationEventsOnlyUpdateTheSelectedPage() async {
        let log = WebCommandLog()
        let (one, two) = (BrowserBookmark.fixture(1), BrowserBookmark.fixture(2))
        let (stream, continuation) = AsyncStream.makeStream(of: BrowserNavigationEvent.self)
        let store = TestStore(initialState: BrowserFeature.State()) { BrowserFeature() } withDependencies: {
            $0.browserStorage = log.storage(.loaded(.init(bookmarks: [one, two], selectedID: one.id)))
            $0.browserWebClient = log.client(events: stream)
        }
        await store.send(.onAppear) {
            $0.hasStarted = true
            $0.bookmarks = [one, two]
            $0.selectedID = one.id
            $0.addressText = "https://site1.example"
        }
        let page = BrowserNavigationState(currentURL: URL(string: "https://site1.example/a"), title: "A", canGoBack: true)
        continuation.yield(BrowserNavigationEvent(bookmarkID: two.id, state: .init(title: "ignored")))
        continuation.yield(BrowserNavigationEvent(bookmarkID: one.id, state: page))
        await store.receive(\.navigationEvent)
        await store.receive(\.navigationEvent) {
            $0.navigation = page
            $0.addressText = "https://site1.example/a"
        }
        continuation.finish()
        await store.finish()
    }

    @Test func addressSubmissionValidatesAndLoadsInTheSelectedPage() async {
        let log = WebCommandLog()
        let one = BrowserBookmark.fixture(1)
        let store = TestStore(initialState: startedState([one], selected: one.id)) { BrowserFeature() } withDependencies: {
            $0.browserWebClient = log.client()
        }
        await store.send(.addressTextChanged("not a url")) { $0.addressText = "not a url" }
        await store.send(.addressSubmitted) { $0.showsInvalidAddress = true }
        await store.send(.addressTextChanged("menubarx.app")) {
            $0.addressText = "menubarx.app"
            $0.showsInvalidAddress = false
        }
        await store.send(.addressSubmitted) { $0.addressText = "https://menubarx.app" }
        await store.finish()
        #expect(log.commands.value == ["load 1 https://menubarx.app"])
    }

    @Test func toolbarCommandsTargetTheSelectedPage() async {
        let log = WebCommandLog()
        let opened = LockIsolated<[URL]>([])
        let one = BrowserBookmark.fixture(1)
        let store = TestStore(initialState: startedState([one], selected: one.id)) { BrowserFeature() } withDependencies: {
            $0.browserWebClient = log.client()
            $0.openURL = OpenURLEffect { url in
                opened.withValue { $0.append(url) }
                return true
            }
        }
        await store.send(.goBackTapped).finish()
        await store.send(.goForwardTapped).finish()
        await store.send(.reloadOrStopTapped).finish()
        await store.send(.navigationEvent(.init(bookmarkID: one.id, state: .init(isLoading: true)))) {
            $0.navigation.isLoading = true
        }
        await store.send(.reloadOrStopTapped).finish()
        await store.send(.homeTapped).finish()
        await store.send(.openInDefaultBrowserTapped).finish()
        #expect(log.commands.value == ["back 1", "forward 1", "reload 1", "stop 1", "load 1 https://site1.example"])
        #expect(opened.value == [one.url])
    }

    @Test func commandsWithoutASelectionDoNothing() async {
        let log = WebCommandLog()
        let store = TestStore(initialState: startedState([], selected: nil)) { BrowserFeature() } withDependencies: {
            $0.browserWebClient = log.client()
        }
        await store.send(.goBackTapped)
        await store.send(.reloadOrStopTapped)
        await store.send(.homeTapped)
        await store.send(.addressSubmitted)
        await store.send(.openInDefaultBrowserTapped)
        #expect(log.commands.value.isEmpty)
    }

    @Test func selectingABookmarkResetsToolbarPersistsAndActivates() async {
        let log = WebCommandLog()
        let (one, two) = (BrowserBookmark.fixture(1), BrowserBookmark.fixture(2))
        var state = startedState([one, two], selected: one.id)
        state.navigation = .init(title: "Old", canGoBack: true)
        let store = TestStore(initialState: state) { BrowserFeature() } withDependencies: {
            $0.browserWebClient = log.client()
            $0.browserStorage = log.storage(.loaded(.init()))
        }
        await store.send(.selectBookmark(two.id)) {
            $0.selectedID = two.id
            $0.navigation = .init()
            $0.addressText = "https://site2.example"
        }
        await store.send(.selectBookmark(two.id))
        await store.send(.selectBookmark(UUID()))
        await store.finish()
        #expect(log.commands.value == ["activate 2"])
        #expect(log.saves.value == [.init(bookmarks: [one, two], selectedID: two.id)])
    }

    @Test func clearingWebsiteDataIsGuardedWhileInFlight() async {
        let clears = LockIsolated(0)
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        let store = TestStore(initialState: startedState([], selected: nil)) { BrowserFeature() } withDependencies: {
            $0.browserWebClient.clearWebsiteData = {
                clears.withValue { $0 += 1 }
                for await _ in gate { break }
            }
        }
        await store.send(.clearWebsiteDataTapped) { $0.isClearingWebsiteData = true }
        await store.send(.clearWebsiteDataTapped)
        release.yield()
        await store.receive(\.clearWebsiteDataFinished) { $0.isClearingWebsiteData = false }
        #expect(clears.value == 1)
    }
}
