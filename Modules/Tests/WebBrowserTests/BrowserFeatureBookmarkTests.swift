import ComposableArchitecture
import Foundation
import Testing
@testable import WebBrowser

@MainActor
struct BrowserFeatureBookmarkTests {
    private let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!

    private func makeStore(_ log: WebCommandLog, bookmarks: [BrowserBookmark], selected: UUID?) -> TestStoreOf<BrowserFeature> {
        var state = BrowserFeature.State()
        state.hasStarted = true
        state.bookmarks = IdentifiedArray(uniqueElements: bookmarks)
        state.selectedID = selected
        let newID = newID
        return TestStore(initialState: state) { BrowserFeature() } withDependencies: {
            $0.browserWebClient = log.client()
            $0.browserStorage = log.storage(.loaded(.init()))
            $0.uuid = .constant(newID)
        }
    }

    @Test func firstBookmarkIsValidatedSavedSelectedAndActivated() async {
        let log = WebCommandLog()
        let store = makeStore(log, bookmarks: [], selected: nil)
        await store.send(.addBookmarkTapped) { $0.draft = BrowserBookmarkDraft() }
        await store.send(.draftAddressChanged("file:///etc")) { $0.draft?.address = "file:///etc" }
        await store.send(.draftSaveTapped) { $0.draft?.showsInvalidAddress = true }
        await store.send(.draftAddressChanged("menubarx.app")) {
            $0.draft?.address = "menubarx.app"
            $0.draft?.showsInvalidAddress = false
        }
        await store.send(.draftMobileUserAgentChanged(true)) { $0.draft?.usesMobileUserAgent = true }
        let added = BrowserBookmark(id: newID, title: "", url: URL(string: "https://menubarx.app")!, usesMobileUserAgent: true)
        await store.send(.draftSaveTapped) {
            $0.draft = nil
            $0.bookmarks = [added]
            $0.selectedID = added.id
            $0.addressText = "https://menubarx.app"
        }
        await store.finish()
        #expect(log.commands.value == ["activate 9"])
        #expect(log.saves.value == [.init(bookmarks: [added], selectedID: added.id)])
    }

    @Test func laterBookmarksAreAppendedWithoutChangingTheSelection() async {
        let log = WebCommandLog()
        let one = BrowserBookmark.fixture(1)
        let store = makeStore(log, bookmarks: [one], selected: one.id)
        await store.send(.addBookmarkTapped) { $0.draft = BrowserBookmarkDraft() }
        await store.send(.draftTitleChanged(" Docs ")) { $0.draft?.title = " Docs " }
        await store.send(.draftAddressChanged("docs.example")) { $0.draft?.address = "docs.example" }
        await store.send(.draftSaveTapped) {
            $0.draft = nil
            $0.bookmarks.append(BrowserBookmark(id: self.newID, title: "Docs", url: URL(string: "https://docs.example")!))
        }
        await store.finish()
        #expect(log.commands.value.isEmpty)
        #expect(log.saves.value.count == 1)
    }

    @Test func editingTheSelectedBookmarkAppliesUserAgentThenLoads() async {
        let log = WebCommandLog()
        let one = BrowserBookmark.fixture(1)
        let store = makeStore(log, bookmarks: [one], selected: one.id)
        await store.send(.editBookmarkTapped(one.id)) {
            $0.draft = BrowserBookmarkDraft(editingID: one.id, title: "Site 1", address: "https://site1.example")
        }
        await store.send(.draftTitleChanged("  Renamed ")) { $0.draft?.title = "  Renamed " }
        await store.send(.draftAddressChanged("https://other.example")) { $0.draft?.address = "https://other.example" }
        await store.send(.draftMobileUserAgentChanged(true)) { $0.draft?.usesMobileUserAgent = true }
        await store.send(.draftSaveTapped) {
            $0.draft = nil
            $0.bookmarks[id: one.id]?.title = "Renamed"
            $0.bookmarks[id: one.id]?.url = URL(string: "https://other.example")!
            $0.bookmarks[id: one.id]?.usesMobileUserAgent = true
            $0.addressText = "https://other.example"
        }
        await store.finish()
        #expect(log.commands.value == ["mobile 1 true", "load 1 https://other.example"])
    }

    @Test func editingAnotherBookmarksAddressReloadsItsLivePageWithoutTouchingTheToolbar() async {
        let log = WebCommandLog()
        let (one, two) = (BrowserBookmark.fixture(1), BrowserBookmark.fixture(2))
        let store = makeStore(log, bookmarks: [one, two], selected: one.id)
        await store.send(.editBookmarkTapped(two.id)) {
            $0.draft = BrowserBookmarkDraft(editingID: two.id, title: "Site 2", address: "https://site2.example")
        }
        await store.send(.draftAddressChanged("moved.example")) { $0.draft?.address = "moved.example" }
        await store.send(.draftSaveTapped) {
            $0.draft = nil
            $0.bookmarks[id: two.id]?.url = URL(string: "https://moved.example")!
        }
        await store.finish()
        #expect(log.commands.value == ["load 2 https://moved.example"])
    }

    @Test func cancelDiscardsTheDraft() async {
        let store = makeStore(WebCommandLog(), bookmarks: [], selected: nil)
        await store.send(.addBookmarkTapped) { $0.draft = BrowserBookmarkDraft() }
        await store.send(.draftCancelTapped) { $0.draft = nil }
    }

    @Test func deletingTheSelectedBookmarkDiscardsItsPageAndSelectsTheNext() async {
        let log = WebCommandLog()
        let (one, two) = (BrowserBookmark.fixture(1), BrowserBookmark.fixture(2))
        let store = makeStore(log, bookmarks: [one, two], selected: one.id)
        await store.send(.deleteBookmarkTapped(one.id)) {
            $0.bookmarks = [two]
            $0.selectedID = two.id
            $0.addressText = "https://site2.example"
        }
        await store.send(.deleteBookmarkTapped(two.id)) {
            $0.bookmarks = []
            $0.selectedID = nil
            $0.addressText = ""
        }
        await store.finish()
        #expect(log.commands.value.filter { $0.hasPrefix("discard") }.sorted() == ["discard 1", "discard 2"])
        #expect(log.commands.value.contains("activate 2"))
        #expect(log.saves.value.last == .init(bookmarks: [], selectedID: nil))
    }

    @Test func toggleMobileMoveAndAddCurrentPage() async {
        let log = WebCommandLog()
        let (one, two) = (BrowserBookmark.fixture(1), BrowserBookmark.fixture(2))
        let store = makeStore(log, bookmarks: [one, two], selected: one.id)
        await store.send(.mobileUserAgentToggled(one.id)) { $0.bookmarks[id: one.id]?.usesMobileUserAgent = true }
        await store.send(.moveBookmarks([1], 0)) { $0.bookmarks = [two, $0.bookmarks[id: one.id]!] }
        await store.send(.navigationEvent(.init(bookmarkID: one.id, state: .init(currentURL: one.url)))) {
            $0.navigation.currentURL = one.url
            $0.addressText = one.url.absoluteString
        }
        // Already bookmarked: no-op.
        await store.send(.addCurrentPageTapped)
        let page = URL(string: "https://site1.example/docs")!
        await store.send(.navigationEvent(.init(bookmarkID: one.id, state: .init(currentURL: page, title: "Docs")))) {
            $0.navigation = .init(currentURL: page, title: "Docs")
            $0.addressText = page.absoluteString
        }
        await store.send(.addCurrentPageTapped) {
            $0.bookmarks.append(BrowserBookmark(id: self.newID, title: "Docs", url: page, usesMobileUserAgent: true))
        }
        await store.finish()
        #expect(log.commands.value == ["mobile 1 true"])
        #expect(log.saves.value.count == 3)
    }
}
