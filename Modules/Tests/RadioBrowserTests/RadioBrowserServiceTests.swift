#if os(macOS)
import Foundation
import Testing
@testable import RadioBrowser

/// Replays canned responses per host and records every request.
private actor FakeTransport {
    var requests: [URLRequest] = []
    private let responses: [String: (status: Int, body: Data)]

    init(_ responses: [String: (status: Int, body: Data)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let host = request.url?.host() ?? ""
        guard let response = responses[host] else { throw URLError(.cannotConnectToHost) }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        return (response.body, http)
    }

    var hosts: [String] { requests.compactMap { $0.url?.host() } }
}

struct RadioBrowserServiceTests {
    private let servers = Data(#"[{"name":"de1.api.radio-browser.info"},{"name":"fi1.api.radio-browser.info"},{"name":"de1.api.radio-browser.info"}]"#.utf8)

    private func service(_ transport: FakeTransport, maxBytes: Int = 1_000_000) -> RadioBrowserService {
        RadioBrowserService(transport: { try await transport.send($0) }, userAgent: "OnlySwitch/9.9", maxBytes: maxBytes)
    }

    @Test func failsOverToTheNextMirrorAndRemembersIt() async throws {
        let transport = FakeTransport([
            RadioBrowserService.discoveryHost: (200, servers),
            "de1.api.radio-browser.info": (503, Data()),
            "fi1.api.radio-browser.info": (200, RadioBrowserFixtures.stationsJSON)
        ])
        let service = service(transport)
        let first = try await service.stations(RadioBrowserQuery())
        #expect(first.count == 2)
        _ = try await service.stations(RadioBrowserQuery(text: "jazz"))
        #expect(await transport.hosts == [
            RadioBrowserService.discoveryHost,
            "de1.api.radio-browser.info",
            "fi1.api.radio-browser.info",
            "fi1.api.radio-browser.info"
        ])
    }

    @Test func usesFallbackMirrorsWhenDiscoveryFails() async throws {
        let fallback = try #require(RadioBrowserService.fallbackHosts.first)
        let transport = FakeTransport([fallback: (200, Data("[]".utf8))])
        let stations = try await service(transport).stations(RadioBrowserQuery())
        #expect(stations.isEmpty)
        #expect(await transport.hosts.first == RadioBrowserService.discoveryHost)
        #expect(await transport.hosts.last == fallback)
    }

    @Test func reportsUnavailableWhenEveryMirrorFails() async {
        let transport = FakeTransport([:])
        await #expect(throws: RadioBrowserError.unavailable) {
            try await service(transport).stations(RadioBrowserQuery())
        }
        #expect(await transport.hosts.count == 1 + RadioBrowserService.fallbackHosts.count)
    }

    @Test func reportsAServerOutageWhenMirrorsAnswerWithErrors() async {
        let transport = FakeTransport([
            RadioBrowserService.discoveryHost: (503, Data("no available server".utf8)),
            "de1.api.radio-browser.info": (503, Data("no available server".utf8))
        ])
        await #expect(throws: RadioBrowserError.serverUnavailable) {
            try await service(transport).stations(RadioBrowserQuery())
        }
    }

    @Test func rejectsOversizedBodies() async {
        let fallback = RadioBrowserService.fallbackHosts[0]
        let transport = FakeTransport([fallback: (200, Data(repeating: 0x20, count: 64))])
        await #expect(throws: RadioBrowserError.invalidResponse) {
            try await service(transport, maxBytes: 32).stations(RadioBrowserQuery())
        }
    }

    @Test func identifiesItselfWithAUserAgent() async throws {
        let fallback = RadioBrowserService.fallbackHosts[0]
        let transport = FakeTransport([fallback: (200, Data("[]".utf8))])
        _ = try await service(transport).tags()
        let request = try #require(await transport.requests.last)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "OnlySwitch/9.9")
        #expect(request.timeoutInterval == RadioBrowserService.timeout)
    }

    @Test func cancellationStopsFailover() async {
        let transport = FakeTransport([:])
        let service = service(transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.stations(RadioBrowserQuery())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.hosts.isEmpty)
    }
}
#endif
