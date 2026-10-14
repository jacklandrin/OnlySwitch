//
//  OpenAIService.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import Dependencies
import DependenciesMacros
import AIProxy
import Foundation
import Sharing

public enum OpenAIError: Error {
    case uninitialized
}

final class OpenAILive: Sendable {
    @Sendable
    func setAPIToken(_ apiToken: String, host: String = "api.openai.com") {
        @Shared(.openAIAPIKey) var apiKeyShared: String = ""
        @Shared(.openAIHost) var hostShared
        guard !apiToken.isEmpty else {
            return
        }
        $apiKeyShared.withLock { $0 = apiToken }
        $hostShared.withLock { $0 = host }
    }
    
    @Sendable
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
    
    @Sendable
    func chatStream(_ model: String, _ prompt: String, systemInstructions: String = AppleScriptSystemPrompt.withCurrentMacOSVersion, maximumOutputTokens: Int? = nil) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        @Shared(.openAIAPIKey) var apiKeyShared: String = ""
        @Shared(.openAIHost) var hostShared
        let apiKey: String = apiKeyShared
        let host: String = hostShared
        
        guard !apiKey.isEmpty else {
            throw OpenAIError.uninitialized
        }
        
        let baseURL: String? = {
            guard !host.isEmpty else { return nil }
            if host.hasPrefix("http://") || host.hasPrefix("https://") {
                return host
            }
            return "https://\(host)"
        }()
        let requestFormat: OpenAIRequestFormat = {
            guard let baseURL else { return .standard }
            if baseURL.contains("/v1") {
                return .noVersionPrefix
            }
            return .standard
        }()
        let openAIService = AIProxy.openAIDirectService(
            unprotectedAPIKey: apiKey,
            baseURL: baseURL,
            requestFormat: requestFormat
        )
        let stream = try await openAIService.streamingChatCompletionRequest(
            body: .init(
                model: model,
                messages: [
                    .system(content: .text(systemInstructions)),
                    .user(content: .text(prompt))
                ],
                maxCompletionTokens: maximumOutputTokens
            ),
            secondsToWait: 120
        )
        
        return AsyncThrowingStream { continuation in
            let worker = Task {
                var finalText = ""
                
                do {
                    for try await chunk in stream {
                        for choice in chunk.choices {
                            guard let delta = choice.delta.content, !delta.isEmpty else { continue }
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
    
    @Sendable
    func test() async -> Bool {
        do {
            let _ = try await chat("gpt-4.1-mini", "Hello")
            return true
        } catch {
            return false
        }
    }
}
