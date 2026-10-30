#if os(macOS)
import Foundation
@testable import RadioBrowser

enum RadioBrowserFixtures {
    static let stationsJSON = Data(#"""
    [
      {"stationuuid":"s1","name":" Jazz FM ","url":"http://stream.example.com/jazz.pls","url_resolved":"https://stream.example.com/jazz.mp3","homepage":"https://jazz.example.com","favicon":"https://example.com/icon.png","tags":"jazz, smooth jazz,","country":"United Kingdom","countrycode":"GB","language":"english","codec":"MP3","bitrate":128,"hls":0,"votes":12,"clickcount":340},
      {"stationuuid":"s2","name":"Broken","url":"ftp://nope","url_resolved":"","favicon":"","tags":"","countrycode":"","codec":"","bitrate":0,"hls":0,"votes":0,"clickcount":0},
      {"stationuuid":"s3","name":"Lofi","url":"https://lofi.example.com/live","url_resolved":"","favicon":"","tags":"","country":"","countrycode":"","codec":"AAC","bitrate":64,"hls":1,"votes":3,"clickcount":4},
      {"stationuuid":"s4","name":"Jazz FM mirror","url":"https://stream.example.com/jazz.mp3/","url_resolved":"","favicon":"","tags":"","countrycode":"","codec":"","bitrate":0,"hls":0,"votes":0,"clickcount":0}
    ]
    """#.utf8)

    static func station(_ id: String, name: String? = nil, url: String? = nil, favicon: String? = nil) -> RadioBrowserStation {
        RadioBrowserStation(
            id: id,
            name: name ?? "Station \(id)",
            streamURL: URL(string: url ?? "https://radio.example.com/\(id)")!,
            homepage: nil,
            favicon: favicon.flatMap(URL.init(string:)),
            tags: ["pop"],
            country: "Germany",
            countryCode: "DE",
            language: "german",
            codec: "MP3",
            bitrate: 128,
            votes: 1,
            clickCount: 1,
            isHLS: false
        )
    }

    static func favorite(_ index: Int, name: String? = nil, url: String? = nil) -> RadioFavorite {
        RadioFavorite(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            name: name ?? "Favorite \(index)",
            streamURL: url ?? "https://favorites.example.com/\(index)",
            favicon: nil,
            browserStationID: nil
        )
    }
}
#endif
