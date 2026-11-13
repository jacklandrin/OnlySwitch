import Foundation
import Testing
@testable import WebBrowser

struct BrowserURLNormalizerTests {
    @Test(arguments: [
        ("example.com", "https://example.com"),
        ("  https://Example.com/path?q=1  ", "https://Example.com/path?q=1"),
        ("HTTP://example.com", "http://example.com"),
        ("localhost:3000", "https://localhost:3000"),
        ("http://192.168.1.2:8080/", "http://192.168.1.2:8080/"),
        ("menubarx.app", "https://menubarx.app"),
    ])
    func acceptsWebAddresses(input: String, expected: String) {
        #expect(BrowserURLNormalizer.url(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "hello world", "javascript:alert(1)", "file:///etc/passwd",
                      "ftp://example.com", "https://", "data:text/html,hi", "about:blank", "intranet"])
    func rejectsEverythingElse(input: String) {
        #expect(BrowserURLNormalizer.url(from: input) == nil)
    }

    @Test func displayTitleFallsBackToHost() throws {
        let url = try #require(URL(string: "https://menubarx.app/docs"))
        #expect(BrowserBookmark(id: UUID(), title: "  ", url: url).displayTitle == "menubarx.app")
        #expect(BrowserBookmark(id: UUID(), title: "Docs", url: url).displayTitle == "Docs")
    }
}
