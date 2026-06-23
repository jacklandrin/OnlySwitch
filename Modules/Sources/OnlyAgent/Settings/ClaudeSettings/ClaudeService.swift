//
//  ClaudeService.swift
//  Modules
//
//  Created by Louis Saks on 23.06.26.
//

import Sharing
import Foundation

final class ClaudeLive: Sendable {
    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"

    @Sendable
    func setAPIKey(_ key: String) {
        @Shared(.claudeAPIKey) var apiKeyShared: String = ""
        guard !key.isEmpty else { return }
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
    func chatStream(_ model: String, _ prompt: String) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> {
        @Shared(.claudeAPIKey) var apiKeyShared: String = ""
        let apiKey: String = apiKeyShared

        guard !apiKey.isEmpty else {
            throw ClaudeError.uninitialized
        }

        var request = URLRequest(url: ClaudeLive.apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(ClaudeLive.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": AppleScriptSystemPrompt.withCurrentMacOSVersion,
            "messages": [["role": "user", "content": prompt]],
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: ClaudeError.invalidResponse)
                        return
                    }

                    var finalText = ""
                    for try await line in asyncBytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]",
                              let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let eventType = json["type"] as? String,
                              eventType == "content_block_delta",
                              let delta = json["delta"] as? [String: Any],
                              (delta["type"] as? String) == "text_delta",
                              let text = delta["text"] as? String,
                              !text.isEmpty
                        else { continue }

                        finalText += text
                        continuation.yield(.contentDelta(text))
                    }
                    continuation.yield(.completed(finalText: finalText))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    @Sendable
    func test() async -> Bool {
        do {
            let _ = try await chat("claude-haiku-4-5-20251001", "Hello")
            return true
        } catch {
            return false
        }
    }
}

public enum ClaudeError: Error {
    case uninitialized
    case invalidResponse
}
