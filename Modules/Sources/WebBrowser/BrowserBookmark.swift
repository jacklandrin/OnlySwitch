import Foundation

public struct BrowserBookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var usesMobileUserAgent: Bool

    public init(id: UUID, title: String, url: URL, usesMobileUserAgent: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.usesMobileUserAgent = usesMobileUserAgent
    }

    /// The trimmed title, or the host when the user left it empty.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (url.host() ?? url.absoluteString) : trimmed
    }
}
