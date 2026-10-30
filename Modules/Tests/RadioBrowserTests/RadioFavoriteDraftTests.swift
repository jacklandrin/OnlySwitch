#if os(macOS)
import Foundation
import Testing
@testable import RadioBrowser

struct RadioFavoriteDraftTests {
    @Test func validDraftIsTrimmed() throws {
        let draft = RadioFavoriteDraft(name: "  Jazz  ", streamURL: " https://jazz.example.com/live \n")
        let valid = try draft.validate(existing: [], editingID: nil).get()
        #expect(valid.name == "Jazz")
        #expect(valid.streamURL == "https://jazz.example.com/live")
    }

    @Test(arguments: [
        ("", "https://a.example.com", RadioFavoriteDraft.Issue.emptyName),
        ("   ", "https://a.example.com", .emptyName),
        ("Name", "", .invalidURL),
        ("Name", "not a url", .invalidURL),
        ("Name", "ftp://a.example.com/stream", .invalidURL),
        ("Name", "https://", .invalidURL)
    ])
    func invalidDraftsReportTheFirstIssue(name: String, url: String, issue: RadioFavoriteDraft.Issue) {
        #expect(RadioFavoriteDraft(name: name, streamURL: url).validate(existing: [], editingID: nil) == .failure(issue))
    }

    @Test func duplicatesIgnoreCaseAndTrailingSlash() {
        let existing = [RadioBrowserFixtures.favorite(1, url: "https://Radio.Example.com/live")]
        let draft = RadioFavoriteDraft(name: "Copy", streamURL: "HTTPS://radio.example.com/live/")
        #expect(draft.validate(existing: existing, editingID: nil) == .failure(.duplicateURL))
    }

    @Test func editingKeepsItsOwnURL() throws {
        let favorite = RadioBrowserFixtures.favorite(1)
        let draft = RadioFavoriteDraft(name: "Renamed", streamURL: favorite.streamURL)
        let valid = try draft.validate(existing: [favorite], editingID: favorite.id).get()
        #expect(valid.name == "Renamed")
    }

    @Test func normalizationKeepsPathCase() {
        #expect(RadioStreamURL.normalized(" HTTP://Example.COM/Live/ ") == "http://example.com/Live")
        #expect(RadioStreamURL.isValid("http://example.com:8000/stream"))
        #expect(!RadioStreamURL.isValid("javascript:alert(1)"))
    }
}
#endif
