import ComposableArchitecture
import CoreGraphics
import Testing
@testable import WebBrowser

@MainActor
struct BrowserViewportTests {
    @Test func startupRestoresViewportAlongsideSelectedPage() async {
        let log = WebCommandLog()
        let bookmark = BrowserBookmark.fixture(1)
        let store = TestStore(initialState: BrowserFeature.State()) { BrowserFeature() } withDependencies: {
            $0.browserStorage = log.storage(.loaded(.init(
                bookmarks: [bookmark], selectedID: bookmark.id, viewportSize: .extraLarge
            )))
            $0.browserWebClient = log.client()
        }
        await store.send(.onAppear) {
            $0.hasStarted = true
            $0.bookmarks = [bookmark]
            $0.selectedID = bookmark.id
            $0.addressText = bookmark.url.absoluteString
            $0.viewportSize = .extraLarge
        }
        await store.finish()
        #expect(log.commands.value == ["activate 1"])
        #expect(log.saves.value.isEmpty)
    }

    @Test func changingViewportPersistsWithoutReloadingThePage() async {
        let log = WebCommandLog()
        let bookmark = BrowserBookmark.fixture(1)
        var state = BrowserFeature.State()
        state.hasStarted = true
        state.bookmarks = [bookmark]
        state.selectedID = bookmark.id
        let store = TestStore(initialState: state) { BrowserFeature() } withDependencies: {
            $0.browserStorage = log.storage(.loaded(.init()))
            $0.browserWebClient = log.client()
        }
        await store.send(.viewportSizeChanged(.compact)) { $0.viewportSize = .compact }
        await store.finish()
        await store.send(.viewportSizeChanged(.compact))
        await store.finish()
        #expect(log.commands.value.isEmpty)
        #expect(log.saves.value == [.init(
            bookmarks: [bookmark], selectedID: bookmark.id, viewportSize: .compact
        )])
    }

    @Test(arguments: [
        (BrowserViewportSize.compact, CGSize(width: 320, height: 568)),
        (.standard, CGSize(width: 375, height: 667)),
        (.large, CGSize(width: 390, height: 844)),
        (.extraLarge, CGSize(width: 430, height: 932)),
    ])
    func presetsUsePortraitPhoneDimensions(_ viewport: BrowserViewportSize, expected: CGSize) {
        #expect(viewport.size == expected)
    }

    @Test(arguments: BrowserViewportSize.allCases)
    func roomyHostsPreserveTheRequestedViewport(_ viewport: BrowserViewportSize) {
        #expect(BrowserLayout.viewportSize(viewport, fitting: CGSize(width: 800, height: 1200)) == viewport.size)
    }

    @Test func shortHostsClampHeightWithoutShrinkingTextWidth() {
        #expect(BrowserLayout.viewportSize(.large, fitting: CGSize(width: 740, height: 450)) == CGSize(width: 390, height: 450))
    }

    @Test func narrowHostsAndUnavailableSpaceNeverOverflow() {
        #expect(BrowserLayout.viewportSize(.extraLarge, fitting: CGSize(width: 300, height: 420)) == CGSize(width: 300, height: 420))
        #expect(BrowserLayout.viewportSize(.standard, fitting: CGSize(width: -1, height: 0)) == .zero)
    }
}
