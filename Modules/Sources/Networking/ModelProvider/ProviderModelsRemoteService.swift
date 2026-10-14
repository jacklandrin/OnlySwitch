//
//  ProviderModelsRemoteService.swift
//  Modules
//
//  Created by Codex on 28.03.26.
//

import Foundation

public actor ProviderModelsRemoteService {
    private let modelsURL = URL(string: "https://raw.githubusercontent.com/jacklandrin/OnlySwitch/main/OnlySwitch/Resource/models.json")!
    private let session: URLSession
    private var cachedResponse: ProviderModelsCatalog?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func models(for provider: RemoteModelProviderKey) async throws -> [String] {
        let response = try await loadResponse()
        return response.models(for: provider)
    }

    private func loadResponse() async throws -> ProviderModelsCatalog {
        if let cachedResponse {
            return cachedResponse
        }

        do {
            var request = URLRequest(url: modelsURL)
            request.timeoutInterval = 30
            request.httpMethod = "GET"
            request.allHTTPHeaderFields = ["Accept": "application/json"]
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw RequestError.failed }
            let remote = try JSONDecoder().decode(ProviderModelsCatalog.self, from: data)
            let resolved = ProviderModelsCatalog.resolve(remote: remote, bundled: try? loadLocalResponse())
            cachedResponse = resolved
            return resolved
        } catch {
            let local = try loadLocalResponse()
            cachedResponse = local
            return local
        }
    }

    private func loadLocalResponse() throws -> ProviderModelsCatalog {
        guard let localURL = Bundle.main.url(forResource: "models", withExtension: "json") else {
            throw RequestError.invalidURL
        }
        let data = try Data(contentsOf: localURL)
        return try JSONDecoder().decode(ProviderModelsCatalog.self, from: data)
    }
}
