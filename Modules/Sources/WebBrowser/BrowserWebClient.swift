import Dependencies
import Foundation

/// The reducer's only path to WebKit: commands for a page (keyed by bookmark ID) and its navigation events.
public struct BrowserWebClient: Sendable {
    /// Navigation state of every live page. A new call replaces the previous stream.
    public var events: @Sendable () async -> AsyncStream<BrowserNavigationEvent>
    /// Shows the bookmark's page, creating and loading it if it is not alive, and reports its current state.
    public var activate: @Sendable (BrowserBookmark) async -> Void
    public var load: @Sendable (UUID, URL) async -> Void
    public var goBack: @Sendable (UUID) async -> Void
    public var goForward: @Sendable (UUID) async -> Void
    public var reload: @Sendable (UUID) async -> Void
    public var stop: @Sendable (UUID) async -> Void
    public var setMobileUserAgent: @Sendable (UUID, Bool) async -> Void
    /// Tears down the page of a deleted bookmark.
    public var discard: @Sendable (UUID) async -> Void
    public var clearWebsiteData: @Sendable () async -> Void

    public init(
        events: @escaping @Sendable () async -> AsyncStream<BrowserNavigationEvent>,
        activate: @escaping @Sendable (BrowserBookmark) async -> Void,
        load: @escaping @Sendable (UUID, URL) async -> Void,
        goBack: @escaping @Sendable (UUID) async -> Void,
        goForward: @escaping @Sendable (UUID) async -> Void,
        reload: @escaping @Sendable (UUID) async -> Void,
        stop: @escaping @Sendable (UUID) async -> Void,
        setMobileUserAgent: @escaping @Sendable (UUID, Bool) async -> Void,
        discard: @escaping @Sendable (UUID) async -> Void,
        clearWebsiteData: @escaping @Sendable () async -> Void
    ) {
        self.events = events
        self.activate = activate
        self.load = load
        self.goBack = goBack
        self.goForward = goForward
        self.reload = reload
        self.stop = stop
        self.setMobileUserAgent = setMobileUserAgent
        self.discard = discard
        self.clearWebsiteData = clearWebsiteData
    }
}

extension BrowserWebClient: DependencyKey {
    public static let liveValue = BrowserWebClient.live
    public static let testValue = Self(
        events: unimplemented("BrowserWebClient.events", placeholder: AsyncStream { $0.finish() }),
        activate: unimplemented("BrowserWebClient.activate"),
        load: unimplemented("BrowserWebClient.load"),
        goBack: unimplemented("BrowserWebClient.goBack"),
        goForward: unimplemented("BrowserWebClient.goForward"),
        reload: unimplemented("BrowserWebClient.reload"),
        stop: unimplemented("BrowserWebClient.stop"),
        setMobileUserAgent: unimplemented("BrowserWebClient.setMobileUserAgent"),
        discard: unimplemented("BrowserWebClient.discard"),
        clearWebsiteData: unimplemented("BrowserWebClient.clearWebsiteData")
    )
}

public extension DependencyValues {
    var browserWebClient: BrowserWebClient {
        get { self[BrowserWebClient.self] }
        set { self[BrowserWebClient.self] = newValue }
    }
}
