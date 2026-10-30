#if os(macOS)
import Foundation
import Testing
@testable import RadioBrowser

struct RadioBrowserEndpointTests {
    private func items(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func popularSearchOrdersByClicksAndHidesBrokenStations() throws {
        let url = RadioBrowserEndpoint.search(RadioBrowserQuery(text: "", category: .popular, offset: 0, limit: 40))
            .url(host: "de1.api.radio-browser.info")
        #expect(url.host() == "de1.api.radio-browser.info")
        #expect(url.path() == "/json/stations/search")
        let query = items(url)
        #expect(query["order"] == "clickcount")
        #expect(query["reverse"] == "true")
        #expect(query["hidebroken"] == "true")
        #expect(query["offset"] == "0")
        #expect(query["limit"] == "40")
        #expect(query["name"] == nil, "An empty search must not filter by name")
    }

    @Test func textCountryAndTagFiltersAreForwarded() {
        let country = RadioBrowserEndpoint.search(RadioBrowserQuery(text: "  jazz fm ", category: .country(code: "DE", name: "Germany"), offset: 80, limit: 40))
            .url(host: "fi1.api.radio-browser.info")
        #expect(items(country)["name"] == "jazz fm")
        #expect(items(country)["countrycode"] == "DE")
        #expect(items(country)["offset"] == "80")

        let tag = RadioBrowserEndpoint.search(RadioBrowserQuery(text: "", category: .tag("lofi"), offset: 0, limit: 40))
            .url(host: "fi1.api.radio-browser.info")
        #expect(items(tag)["tag"] == "lofi")
        #expect(items(tag)["tagExact"] == "true")

        let voted = RadioBrowserEndpoint.search(RadioBrowserQuery(text: "", category: .topVoted, offset: 0, limit: 40))
            .url(host: "fi1.api.radio-browser.info")
        #expect(items(voted)["order"] == "votes")
    }

    @Test func filterAndClickEndpoints() {
        let countries = RadioBrowserEndpoint.countries.url(host: "h")
        #expect(countries.path() == "/json/countries")
        #expect(items(countries)["order"] == "stationcount")
        let tags = RadioBrowserEndpoint.tags(limit: 60).url(host: "h")
        #expect(tags.path() == "/json/tags")
        #expect(items(tags)["limit"] == "60")
        let click = RadioBrowserEndpoint.click(stationID: "abc-123").url(host: "h")
        #expect(click.path() == "/json/url/abc-123")
    }

    @Test func decodingPrefersResolvedStreamsAndDropsUnusableStations() throws {
        let stations = try RadioBrowserDecoding.stations(from: RadioBrowserFixtures.stationsJSON)
        #expect(stations.map(\.id) == ["s1", "s3"])
        let first = try #require(stations.first)
        #expect(first.name == "Jazz FM")
        #expect(first.streamURL.absoluteString == "https://stream.example.com/jazz.mp3")
        #expect(first.tags == ["jazz", "smooth jazz"])
        #expect(first.favicon?.absoluteString == "https://example.com/icon.png")
        #expect(first.countryCode == "GB")
        #expect(first.codec == "MP3")
        #expect(first.bitrate == 128)
        #expect(first.isHLS == false)
        #expect(stations[1].favicon == nil, "An empty favicon becomes nil")
        #expect(stations[1].tags.isEmpty)
    }

    @Test func decodingFiltersCountriesAndTagsWithoutStations() throws {
        let countries = try RadioBrowserDecoding.countries(from: Data(#"[{"name":"Germany","iso_3166_1":"DE","stationcount":10},{"name":"Nowhere","iso_3166_1":"","stationcount":0},{"name":"Austria","iso_3166_1":"AT","stationcount":4}]"#.utf8))
        #expect(countries == [RadioBrowserCountry(code: "AT", name: "Austria", stationCount: 4), RadioBrowserCountry(code: "DE", name: "Germany", stationCount: 10)])
        let tags = try RadioBrowserDecoding.tags(from: Data(#"[{"name":"pop","stationcount":50},{"name":"","stationcount":9},{"name":"jazz","stationcount":0}]"#.utf8))
        #expect(tags == [RadioBrowserTag(name: "pop", stationCount: 50)])
    }

    @Test func malformedPayloadThrowsInvalidResponse() {
        #expect(throws: RadioBrowserError.invalidResponse) {
            try RadioBrowserDecoding.stations(from: Data("<html>".utf8))
        }
    }
}
#endif
