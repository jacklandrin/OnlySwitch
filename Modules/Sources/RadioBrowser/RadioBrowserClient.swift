import Dependencies
import Foundation

/// Network access to radio-browser.info.
public struct RadioBrowserClient: Sendable {
    public var search: @Sendable (RadioBrowserQuery) async throws -> [RadioBrowserStation]
    public var countries: @Sendable () async throws -> [RadioBrowserCountry]
    public var tags: @Sendable () async throws -> [RadioBrowserTag]
    /// Reports a play to radio-browser's community click counter; failures are ignored.
    public var registerClick: @Sendable (String) async -> Void

    public init(
        search: @escaping @Sendable (RadioBrowserQuery) async throws -> [RadioBrowserStation],
        countries: @escaping @Sendable () async throws -> [RadioBrowserCountry],
        tags: @escaping @Sendable () async throws -> [RadioBrowserTag],
        registerClick: @escaping @Sendable (String) async -> Void
    ) {
        self.search = search; self.countries = countries; self.tags = tags; self.registerClick = registerClick
    }
}

extension RadioBrowserClient: DependencyKey {
    public static let liveValue: Self = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = RadioBrowserService.timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let service = RadioBrowserService(
            transport: { try await session.data(for: $0) },
            userAgent: "OnlySwitch/\(version)"
        )
        return Self(
            search: { try await service.stations($0) },
            countries: { try await service.countries() },
            tags: { try await service.tags() },
            registerClick: { await service.registerClick($0) }
        )
    }()

    public static let testValue = Self(
        search: unimplemented("RadioBrowserClient.search", placeholder: []),
        countries: unimplemented("RadioBrowserClient.countries", placeholder: []),
        tags: unimplemented("RadioBrowserClient.tags", placeholder: []),
        registerClick: unimplemented("RadioBrowserClient.registerClick")
    )
}

public extension DependencyValues {
    var radioBrowserClient: RadioBrowserClient {
        get { self[RadioBrowserClient.self] }
        set { self[RadioBrowserClient.self] = newValue }
    }
}

/// Talks to the community-run radio-browser mirrors, failing over between them.
actor RadioBrowserService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let discoveryHost = "all.api.radio-browser.info"
    static let fallbackHosts = ["de1.api.radio-browser.info", "de2.api.radio-browser.info", "fi1.api.radio-browser.info"]
    static let timeout: TimeInterval = 15
    static let defaultMaxBytes = 2 * 1024 * 1024

    private let transport: Transport
    private let userAgent: String
    private let maxBytes: Int
    private var hosts: [String]?
    private var preferredHost: String?

    init(transport: @escaping Transport, userAgent: String, maxBytes: Int = RadioBrowserService.defaultMaxBytes) {
        self.transport = transport
        self.userAgent = userAgent
        self.maxBytes = maxBytes
    }

    func stations(_ query: RadioBrowserQuery) async throws -> [RadioBrowserStation] {
        try RadioBrowserDecoding.stations(from: await data(for: .search(query)))
    }

    func countries() async throws -> [RadioBrowserCountry] {
        try RadioBrowserDecoding.countries(from: await data(for: .countries))
    }

    func tags() async throws -> [RadioBrowserTag] {
        try RadioBrowserDecoding.tags(from: await data(for: .tags(limit: 80)))
    }

    func registerClick(_ stationID: String) async {
        _ = try? await data(for: .click(stationID: stationID))
    }

    private func data(for endpoint: RadioBrowserEndpoint) async throws -> Data {
        try Task.checkCancellation()
        var candidates = await mirrorHosts()
        if let preferredHost, let index = candidates.firstIndex(of: preferredHost) {
            candidates.insert(candidates.remove(at: index), at: 0)
        }
        var reachedServer = false
        for host in candidates {
            try Task.checkCancellation()
            switch try await fetch(endpoint.url(host: host)) {
            case let .success(body):
                preferredHost = host
                return body
            case .serverError:
                reachedServer = true
            case .unreachable:
                continue
            }
        }
        throw reachedServer ? RadioBrowserError.serverUnavailable : RadioBrowserError.unavailable
    }

    private enum FetchOutcome {
        case success(Data)
        /// The mirror answered with a non-2xx status; try the next one.
        case serverError
        /// The mirror could not be reached; try the next one.
        case unreachable
    }

    private func fetch(_ url: URL) async throws -> FetchOutcome {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return .unreachable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return .serverError }
        guard data.count <= maxBytes else { throw RadioBrowserError.invalidResponse }
        return .success(data)
    }

    private func mirrorHosts() async -> [String] {
        if let hosts { return hosts }
        var discovered: [String] = []
        if let url = URL(string: "https://\(Self.discoveryHost)/json/servers"),
           case let .success(data)? = try? await fetch(url),
           let servers = try? JSONDecoder().decode([Server].self, from: data) {
            for server in servers where server.name.hasSuffix(".radio-browser.info") && !discovered.contains(server.name) {
                discovered.append(server.name)
            }
        }
        // Only cache a successful discovery so a transient outage is retried next time.
        if !discovered.isEmpty { hosts = discovered }
        return discovered.isEmpty ? Self.fallbackHosts : discovered
    }

    private struct Server: Decodable {
        var name: String
    }
}
