import Foundation

/// The radio-browser.info JSON endpoints OnlySwitch uses, independent of which mirror serves them.
enum RadioBrowserEndpoint: Equatable, Sendable {
    case search(RadioBrowserQuery)
    case countries
    case tags(limit: Int)
    case click(stationID: String)

    func url(host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        switch self {
        case let .search(query):
            components.path = "/json/stations/search"
            var items: [URLQueryItem] = []
            if !query.trimmedText.isEmpty {
                items.append(URLQueryItem(name: "name", value: query.trimmedText))
            }
            switch query.category {
            case .popular, .topVoted:
                break
            case let .country(code, _):
                items.append(URLQueryItem(name: "countrycode", value: code))
            case let .tag(tag):
                items.append(URLQueryItem(name: "tag", value: tag))
                items.append(URLQueryItem(name: "tagExact", value: "true"))
            }
            items += [
                URLQueryItem(name: "order", value: query.category == .topVoted ? "votes" : "clickcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "offset", value: String(max(0, query.offset))),
                URLQueryItem(name: "limit", value: String(max(1, query.limit)))
            ]
            components.queryItems = items
        case .countries:
            components.path = "/json/countries"
            components.queryItems = [
                URLQueryItem(name: "order", value: "stationcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "hidebroken", value: "true")
            ]
        case let .tags(limit):
            components.path = "/json/tags"
            components.queryItems = [
                URLQueryItem(name: "order", value: "stationcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        case let .click(stationID):
            components.path = "/json/url/\(stationID)"
        }
        // Every value above is either fixed or percent-encoded by URLComponents.
        return components.url!
    }
}

enum RadioBrowserDecoding {
    private struct StationDTO: Decodable {
        var stationuuid: String
        var name: String?
        var url: String?
        var url_resolved: String?
        var homepage: String?
        var favicon: String?
        var tags: String?
        var country: String?
        var countrycode: String?
        var language: String?
        var codec: String?
        var bitrate: Int?
        var hls: Int?
        var votes: Int?
        var clickcount: Int?
    }

    private struct CountryDTO: Decodable {
        var name: String
        var iso_3166_1: String
        var stationcount: Int
    }

    private struct TagDTO: Decodable {
        var name: String
        var stationcount: Int
    }

    static func stations(from data: Data) throws -> [RadioBrowserStation] {
        let dtos = try decode([StationDTO].self, from: data)
        var seen = Set<String>()
        return dtos.compactMap { dto -> RadioBrowserStation? in
            guard let stream = streamURL(dto.url_resolved) ?? streamURL(dto.url) else { return nil }
            let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, seen.insert(RadioStreamURL.normalized(stream.absoluteString)).inserted else { return nil }
            return RadioBrowserStation(
                id: dto.stationuuid,
                name: name,
                streamURL: stream,
                homepage: webURL(dto.homepage),
                favicon: webURL(dto.favicon),
                tags: (dto.tags ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                country: dto.country ?? "",
                countryCode: dto.countrycode ?? "",
                language: dto.language ?? "",
                codec: dto.codec ?? "",
                bitrate: dto.bitrate ?? 0,
                votes: dto.votes ?? 0,
                clickCount: dto.clickcount ?? 0,
                isHLS: dto.hls == 1
            )
        }
    }

    static func countries(from data: Data) throws -> [RadioBrowserCountry] {
        try decode([CountryDTO].self, from: data)
            .filter { $0.stationcount > 0 && $0.iso_3166_1.count == 2 && !$0.name.isEmpty }
            .map { RadioBrowserCountry(code: $0.iso_3166_1.uppercased(), name: $0.name, stationCount: $0.stationcount) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func tags(from data: Data) throws -> [RadioBrowserTag] {
        try decode([TagDTO].self, from: data)
            .filter { $0.stationcount > 0 && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { RadioBrowserTag(name: $0.name, stationCount: $0.stationcount) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RadioBrowserError.invalidResponse
        }
    }

    private static func streamURL(_ string: String?) -> URL? {
        guard let string, RadioStreamURL.isValid(string) else { return nil }
        return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func webURL(_ string: String?) -> URL? {
        streamURL(string)
    }
}
