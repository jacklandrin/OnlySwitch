import Foundation

public enum BrowserNavigationDecision: Equatable, Sendable {
    case allow
    case openExternally
    case cancel
}

/// Which navigations the embedded browser performs itself, hands to the system, or drops.
public enum BrowserNavigationPolicy {
    static let webSchemes: Set<String> = ["http", "https", "about", "blob"]
    static let externalSchemes: Set<String> = ["mailto", "tel", "sms", "facetime"]

    public static func decision(for url: URL?, isMainFrame: Bool, isUserInitiated: Bool) -> BrowserNavigationDecision {
        guard let scheme = url?.scheme?.lowercased() else { return .cancel }
        if webSchemes.contains(scheme) { return .allow }
        if scheme == "data" { return isMainFrame ? .cancel : .allow }
        if externalSchemes.contains(scheme) { return isUserInitiated ? .openExternally : .cancel }
        return .cancel
    }
}
