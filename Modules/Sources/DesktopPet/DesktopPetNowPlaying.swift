import Foundation

public struct DesktopPetNowPlaying: Equatable, Sendable {
    public var title: String
    public var subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    /// Music apps report the song name and artist. Without a song name there is nothing to show.
    public static func track(name: String?, artist: String?) -> Self? {
        guard let title = name?.trimmed, !title.isEmpty else { return nil }
        let subtitle = artist?.trimmed
        return Self(title: title, subtitle: subtitle?.isEmpty == false ? subtitle : nil)
    }

    /// Radio shows the stream's metadata, or the station name until the stream reports any.
    public static func radio(stationName: String, streamInfo: String) -> Self? {
        let streamInfo = streamInfo.trimmed
        let title = streamInfo.isEmpty ? stationName.trimmed : streamInfo
        return title.isEmpty ? nil : Self(title: title)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
