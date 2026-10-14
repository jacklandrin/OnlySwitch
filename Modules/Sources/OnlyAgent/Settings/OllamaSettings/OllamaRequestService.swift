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
        let stream = try await chatStream(model, prompt)
        var finalText = ""
        
        for try await event in stream {
            switch event {
            case let .contentDelta(delta):
                finalText += delta
            case let .completed(text):
                finalText = text
            case .thinkingDelta:
                break
            }
        }
        
        return finalText
    }
    
    func chatStream(_ model: String, _ prompt: String, systemInstructions: String = AppleScriptSystemPrompt.withCurrentMacOSVersion) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        let client = await MainActor.run { getOrCreateClient() }
        let stream = try await MainActor.run {
            try client.chatStream(
                model: Model.ID(rawValue: model) ?? "gpt-oss",
                messages: [
                    .system(systemInstructions),
                    .user(prompt)
                ],
                think: true
            )
        }
        
        return AsyncThrowingStream { continuation in
            let worker = Task {
                var finalText = ""
                
                do {
                    for try await response in stream {
                        if let thinking = response.message.thinking, !thinking.isEmpty {
                            continuation.yield(.thinkingDelta(thinking))
                        }
                        
                        let delta = response.message.content
                        if !delta.isEmpty {
                            finalText += delta
                            continuation.yield(.contentDelta(delta))
                        }
                    }
                    
                    continuation.yield(.completed(finalText: finalText))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}
