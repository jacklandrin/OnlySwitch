//
//  GeminiService.swift
//  Modules
//
//  Created by Bo Liu on 05.12.25.
//

import Dependencies
import DependenciesMacros
import Sharing
import Foundation
import AIProxy

final class GeminiLive: Sendable {
    @Sendable
    func setAPIKey(_ key: String) {
        @Shared(.geminiAPIKey) var apiKeyShared: String = ""
        guard !key.isEmpty else {
            return
        }
        
        $apiKeyShared.withLock { $0 = key }
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
    func chatStream(_ model: String, _ prompt: String, systemInstructions: String = AppleScriptSystemPrompt.withCurrentMacOSVersion, maximumOutputTokens: Int = 1024) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        @Shared(.geminiAPIKey) var apiKeyShared: String = ""
        let apiKey: String = apiKeyShared
        
        guard !apiKey.isEmpty else {
            throw GeminiError.uninitialized
        }
        
        let geminiService = AIProxy.geminiDirectService(unprotectedAPIKey: apiKey)
        let requestBody = GeminiGenerateContentRequestBody(
            contents: [
                .init(
                    parts: [
                        .text(prompt)
                    ],
                    role: "user"
                )
            ],
            generationConfig: .init(maxOutputTokens: maximumOutputTokens),
            systemInstruction: .init(
                parts: [
                    .text(systemInstructions)
                ]
            )
        )

        let responseStream = try await geminiService.generateStreamingContentRequest(
            body: requestBody,
            model: model,
            secondsToWait: 120
        )
        
        return AsyncThrowingStream { continuation in
            let worker = Task {
                var finalText = ""
                
                do {
                    for try await response in responseStream {
                        guard let candidates = response.candidates else { continue }
                        for candidate in candidates {
                            guard let parts = candidate.content?.parts else { continue }
                            for part in parts {
                                guard case let .text(text) = part, !text.isEmpty else { continue }
                                finalText += text
                                continuation.yield(.contentDelta(text))
                            }
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
            let _ = try await chat("gemini-2.5-pro", "Hello")
            return true
        } catch {
            return false
        }
    }
}

public enum GeminiError: Error {
    case uninitialized
    case invalidResponse
}
