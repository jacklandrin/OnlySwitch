import Foundation
import Testing
@testable import WebBrowser

struct BrowserStorageTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "BrowserStorageTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test func missingValueLoadsEmptyState() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(BrowserStorageClient.userDefaults(defaults).load() == .loaded(BrowserStoredState()))
    }

    @Test func roundTripsBookmarksAndSelection() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try #require(URL(string: "https://menubarx.app"))
        let bookmark = BrowserBookmark(id: UUID(), title: "MenubarX", url: url, usesMobileUserAgent: true)
        let state = BrowserStoredState(bookmarks: [bookmark], selectedID: bookmark.id)
        let client = BrowserStorageClient.userDefaults(defaults)
        try client.save(state)
        #expect(client.load() == .loaded(state))
    }

    @Test func legacyStorageWithoutViewportPreservesBookmarksAndSelection() throws {
        let bookmark = BrowserBookmark.fixture(1)
        let oldJSON = try JSONSerialization.data(withJSONObject: [
            "bookmarks": [[
                "id": bookmark.id.uuidString,
                "title": bookmark.title,
                "url": bookmark.url.absoluteString,
                "usesMobileUserAgent": false,
            ]],
            "selectedID": bookmark.id.uuidString,
        ])
        let restored = try JSONDecoder().decode(BrowserStoredState.self, from: oldJSON)
        #expect(restored == BrowserStoredState(bookmarks: [bookmark], selectedID: bookmark.id, viewportSize: .standard))
    }

    @Test(arguments: BrowserViewportSize.allCases)
    func roundTripsViewportSelection(_ viewport: BrowserViewportSize) throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = BrowserStoredState(viewportSize: viewport)
        let client = BrowserStorageClient.userDefaults(defaults)
        try client.save(state)
        #expect(client.load() == .loaded(state))
    }

    @Test func undecodableValueIsReportedAndLeftUntouched() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("nope".utf8), forKey: "browserStateKey")
        #expect(BrowserStorageClient.userDefaults(defaults).load() == .corrupted)
        #expect(defaults.data(forKey: "browserStateKey") == Data("nope".utf8))
    }
}
