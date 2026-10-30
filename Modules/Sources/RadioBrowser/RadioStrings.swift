import Extensions
import Foundation

/// Every user-facing radio string key, so the localization test can check the catalog.
public enum RadioStrings {
    public static let keys = [
        "Radio Favorites", "Radio Browse", "Radio Search Favorites", "Radio Search Stations",
        "Radio Add Manually", "Radio Add Station", "Radio Edit Station", "Radio Station Name", "Radio Stream URL",
        "Radio Station Name Placeholder", "Radio Stream URL Placeholder", "Radio Stream URL Hint",
        "Radio Save", "Radio Cancel", "Radio Delete", "Radio Edit", "Radio Play", "Radio Stop", "Radio Copy URL",
        "Radio Delete Station Title %@", "Radio Delete Station Message",
        "Radio Import", "Radio Export", "Radio Import Export Help", "Radio More",
        "Radio Now Playing", "Radio Previewing", "Radio Preview", "Radio Stop Preview",
        "Radio Add To Favorites", "Radio In Favorites",
        "Radio Popular", "Radio Top Voted", "Radio Country", "Radio Tag",
        "Radio Load More", "Radio Retry", "Radio Browse Unavailable", "Radio Browse Server Unavailable", "Radio No Results", "Radio No Results Message",
        "Radio No Favorites", "Radio No Favorites Message", "Radio Browse Stations",
        "Radio Powered By",
        "Radio Issue Empty Name", "Radio Issue Invalid URL", "Radio Issue Duplicate URL",
        "Radio Message Added %@", "Radio Message Already Added %@", "Radio Message Saved %@", "Radio Message Deleted %@",
        "Radio Message Imported %lld", "Radio Message Exported", "Radio Message At Least One"
    ]

    public static func text(_ key: String) -> String {
        key.localized()
    }

    static func deleteTitle(_ name: String) -> String {
        "Radio Delete Station Title %@".localizeWithFormat(arguments: name)
    }
}

public extension RadioMessage {
    var text: String {
        switch self {
        case let .added(name): "Radio Message Added %@".localizeWithFormat(arguments: name)
        case let .alreadyInFavorites(name): "Radio Message Already Added %@".localizeWithFormat(arguments: name)
        case let .saved(name): "Radio Message Saved %@".localizeWithFormat(arguments: name)
        case let .deleted(name): "Radio Message Deleted %@".localizeWithFormat(arguments: name)
        case let .imported(count): "Radio Message Imported %lld".localizeWithFormat(arguments: count)
        case .exported: RadioStrings.text("Radio Message Exported")
        case .atLeastOneStation: RadioStrings.text("Radio Message At Least One")
        case let .failure(detail): detail
        }
    }
}

public extension RadioFavoriteDraft.Issue {
    var text: String {
        switch self {
        case .emptyName: RadioStrings.text("Radio Issue Empty Name")
        case .invalidURL: RadioStrings.text("Radio Issue Invalid URL")
        case .duplicateURL: RadioStrings.text("Radio Issue Duplicate URL")
        }
    }
}
