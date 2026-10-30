import Foundation

/// A station returned by radio-browser.info, reduced to the fields OnlySwitch renders or stores.
public struct RadioBrowserStation: Equatable, Hashable, Sendable, Identifiable {
    /// The radio-browser `stationuuid`.
    public var id: String
    public var name: String
    public var streamURL: URL
    public var homepage: URL?
    public var favicon: URL?
    public var tags: [String]
    public var country: String
    public var countryCode: String
    public var language: String
    public var codec: String
    public var bitrate: Int
    public var votes: Int
    public var clickCount: Int
    public var isHLS: Bool

    public init(id: String, name: String, streamURL: URL, homepage: URL?, favicon: URL?, tags: [String], country: String, countryCode: String, language: String, codec: String, bitrate: Int, votes: Int, clickCount: Int, isHLS: Bool) {
        self.id = id; self.name = name; self.streamURL = streamURL; self.homepage = homepage; self.favicon = favicon
        self.tags = tags; self.country = country; self.countryCode = countryCode; self.language = language
        self.codec = codec; self.bitrate = bitrate; self.votes = votes; self.clickCount = clickCount; self.isHLS = isHLS
    }
}

public struct RadioBrowserCountry: Equatable, Hashable, Sendable, Identifiable {
    /// ISO 3166-1 alpha-2 code.
    public var code: String
    public var name: String
    public var stationCount: Int
    public var id: String { code }
    public init(code: String, name: String, stationCount: Int) {
        self.code = code; self.name = name; self.stationCount = stationCount
    }
}

public struct RadioBrowserTag: Equatable, Hashable, Sendable, Identifiable {
    public var name: String
    public var stationCount: Int
    public var id: String { name }
    public init(name: String, stationCount: Int) {
        self.name = name; self.stationCount = stationCount
    }
}

public enum RadioBrowserCategory: Equatable, Hashable, Sendable {
    case popular
    case topVoted
    case country(code: String, name: String)
    case tag(String)
}

public struct RadioBrowserQuery: Equatable, Sendable {
    public static let pageSize = 40

    public var text: String
    public var category: RadioBrowserCategory
    public var offset: Int
    public var limit: Int

    public init(text: String = "", category: RadioBrowserCategory = .popular, offset: Int = 0, limit: Int = RadioBrowserQuery.pageSize) {
        self.text = text; self.category = category; self.offset = offset; self.limit = limit
    }

    public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

public enum RadioBrowserError: Error, Equatable, Sendable {
    /// No mirror could be reached, usually because the Mac is offline.
    case unavailable
    /// Mirrors were reached but answered with server errors (radio-browser.info outage).
    case serverUnavailable
    /// A mirror answered with an unexpected status, body size or payload.
    case invalidResponse
}
