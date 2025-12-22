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
import Alamofire

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
    func models() -> [ProviderModel] {
        [
            "gemini-3-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite"
        ]
            .map(ProviderModel.init)
    }
    
    @Sendable
    func chat(_ model: String, _ prompt: String) async throws -> String {
        @Shared(.geminiAPIKey) var apiKeyShared: String = ""
        let apiKey: String = apiKeyShared
        
        guard !apiKey.isEmpty else {
            throw GeminiError.uninitialized
        }
        
        var urlComponents = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = urlComponents.url else {
            throw GeminiError.invalidURL
        }
        
        let systemInstruction = "You are an AppleScript expert. You generate executable AppleScript code (NOT shell scripts) for macOS automation. Always use AppleScript syntax with 'tell application' commands. Never output shell scripts or bash commands directly."
        
        let requestBody = GeminiRequest(
            contents: GeminiContent(
                parts: GeminiPart(text: prompt),
                role: "user"
            ),
            systemInstruction: GeminiSystemInstruction(
                parts: GeminiPart(text: systemInstruction),
                role: "model"
            )
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let dataResponse = await AF.request(
            url,
            method: .post,
            parameters: requestBody,
            encoder: JSONParameterEncoder(encoder: encoder)
        )
        .serializingDecodable(GeminiResponse.self, decoder: decoder)
        .response
        
        // Check for HTTP errors
        if let httpResponse = dataResponse.response,
           !(200...299).contains(httpResponse.statusCode) {
            if let data = dataResponse.data,
               let errorString = String(data: data, encoding: .utf8) {
                print("Gemini API Error: \(errorString)")
            }
            throw GeminiError.requestFailed
        }
        
        // Check if we got valid data
        guard let response = dataResponse.value else {
            if let error = dataResponse.error {
                print("Alamofire Error: \(error.localizedDescription)")
            }
            if let data = dataResponse.data {
                print("Response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            }
            throw GeminiError.invalidResponse
        }
        
        guard let text = response.candidates?.first?.content?.parts.first?.text else {
            throw GeminiError.invalidResponse
        }
        
        return text
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
    case invalidURL
    case requestFailed
    case invalidResponse
}

// MARK: - Request Models

private struct GeminiRequest: Codable {
    let contents: GeminiContent
    let systemInstruction: GeminiSystemInstruction
}

private struct GeminiContent: Codable {
    let parts: GeminiPart
    let role: String
}

private struct GeminiSystemInstruction: Codable {
    let parts: GeminiPart
    let role: String
}

private struct GeminiPart: Codable {
    let text: String
}

// MARK: - Response Models

private struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
}

private struct GeminiCandidate: Codable {
    let content: GeminiResponseContent?
}

private struct GeminiResponseContent: Codable {
    let parts: [GeminiPart]
    let role: String
}
