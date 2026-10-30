import Foundation

/// A station in the user's radio list (persisted by the app as `RadioStations`).
public struct RadioFavorite: Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var streamURL: String
    public var favicon: URL?
    /// The radio-browser `stationuuid` when the station was added from the browser.
    public var browserStationID: String?

    public init(id: UUID, name: String, streamURL: String, favicon: URL?, browserStationID: String?) {
        self.id = id; self.name = name; self.streamURL = streamURL; self.favicon = favicon; self.browserStationID = browserStationID
    }

    public var host: String {
        URL(string: streamURL)?.host() ?? streamURL
    }
}

/// User input for adding or editing a station by hand.
public struct RadioFavoriteDraft: Equatable, Sendable {
    public enum Issue: Error, Equatable, Sendable {
        case emptyName
        case invalidURL
        case duplicateURL
    }

    /// A draft that passed validation; its values are trimmed.
    public struct Valid: Equatable, Sendable {
        public var name: String
        public var streamURL: String
        public init(name: String, streamURL: String) {
            self.name = name; self.streamURL = streamURL
        }
    }

    public var name: String
    public var streamURL: String

    public init(name: String, streamURL: String) {
        self.name = name; self.streamURL = streamURL
    }

    public func validate(existing: [RadioFavorite], editingID: UUID?) -> Result<Valid, Issue> {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.emptyName) }
        guard RadioStreamURL.isValid(url) else { return .failure(.invalidURL) }
        let normalized = RadioStreamURL.normalized(url)
        if existing.contains(where: { $0.id != editingID && RadioStreamURL.normalized($0.streamURL) == normalized }) {
            return .failure(.duplicateURL)
        }
        return .success(Valid(name: name, streamURL: url))
    }
}

public enum RadioStreamURL {
    /// Only http(s) URLs with a host can be streamed.
    public static func isValid(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return false }
        return true
    }

    /// A comparison key: scheme and host are case-insensitive and a trailing slash is ignored.
    public static func normalized(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return trimmed.lowercased() }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        var result = components.string ?? trimmed
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

/// What the shared radio player is doing, as far as the radio settings page cares.
public struct RadioPlaybackStatus: Equatable, Sendable {
    public var currentID: UUID?
    public var isPlaying: Bool
    /// Set while a browser station is being auditioned instead of a favorite.
    public var previewingStationID: String?

    public init(currentID: UUID? = nil, isPlaying: Bool = false, previewingStationID: String? = nil) {
        self.currentID = currentID; self.isPlaying = isPlaying; self.previewingStationID = previewingStationID
    }
}

public enum RadioLibraryError: Error, Equatable, Sendable {
    case atLeastOneStation
    case storeUnavailable(String)
    case importFailed(String)
    case exportFailed(String)
}
