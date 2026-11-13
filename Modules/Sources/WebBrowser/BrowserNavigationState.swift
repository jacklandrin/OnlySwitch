import Foundation

/// What the toolbar shows for the visible page.
public struct BrowserNavigationState: Equatable, Sendable {
    public var currentURL: URL?
    public var title: String
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool
    public var progress: Double
    /// Localized system description of the last failed load; cleared when a new load starts.
    public var failureDescription: String?

    public init(
        currentURL: URL? = nil,
        title: String = "",
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isLoading: Bool = false,
        progress: Double = 0,
        failureDescription: String? = nil
    ) {
        self.currentURL = currentURL
        self.title = title
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.progress = progress
        self.failureDescription = failureDescription
    }
}

public struct BrowserNavigationEvent: Equatable, Sendable {
    public var bookmarkID: UUID
    public var state: BrowserNavigationState

    public init(bookmarkID: UUID, state: BrowserNavigationState) {
        self.bookmarkID = bookmarkID
        self.state = state
    }
}
