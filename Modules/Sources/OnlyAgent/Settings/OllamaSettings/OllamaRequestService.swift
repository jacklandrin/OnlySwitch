//
//  OllamaRequestService.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Dependencies
import Alamofire
import Sharing
import Foundation
import Ollama

@available(macOS 26.0, *)
final class OllamaLive: Sendable {
    private let client = LockIsolated<Client?>(nil)
    
    @MainActor
    private func getOrCreateClient() -> Client {
        if let existing = client.value {
            return existing
        }
        @Shared(.ollamaUrl) var ollamaUrl: String
        let url = URL(string: ollamaUrl) ?? URL(string: "http://localhost:11434")!
        let newClient = Client(host: url)
        client.setValue(newClient)
        return newClient
    }
    
    @Sendable
    func setHost(host: String) {
        @Shared(.ollamaUrl) var ollamaUrl: String
        $ollamaUrl.withLock { $0 = host }
        Task { @MainActor in
            let url = URL(string: host) ?? URL(string: "http://localhost:11434")!
            let newClient = Client(host: url)
            client.setValue(newClient)
        }
    }
    
    func models() async throws -> [ProviderModel] {
        let client = await MainActor.run { getOrCreateClient() }
        // Use the Ollama Swift client to list models and map to ProviderModel
        let names = try await client.listModels().models.map(\.name)
        return names.map { ProviderModel(model: $0, id: $0) }
    }
    
    func chat(_ model: String, _ prompt: String) async throws -> String {
        let client = await MainActor.run { getOrCreateClient() }
        let response = try await client.chat(model: Model.ID(rawValue: model) ?? "gpt-oss", messages: [.user(prompt)])
        return response.message.content
    }
}

