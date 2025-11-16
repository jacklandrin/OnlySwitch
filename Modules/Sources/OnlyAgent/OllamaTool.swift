//
//  OllamaTool.swift
//  Modules
//
//  Created by Bo Liu on 16.11.25.
//

import FoundationModels
import Foundation

@available(macOS 26.0, *)
final class OllamaTool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "The prompt about apple script generation to request external Ollama AI models")
        let prompt: String
        let model: String
    }
    
    struct RequestBody: Codable, Sendable {
        let model: String
        let prompt: String
        var stream = false
    }
    
    struct ResponseBody: Codable, Sendable {
        let model: String
        let response: String
        let done: Bool
        let thinking: String?
    }
    
    let description = "Request external Ollama AI models by a prompt"
    let name = "OllamaModels"
    
    func call(arguments: Arguments) async throws -> String {
        print("model:\(arguments.model) prompt:\(arguments.prompt)")
        let requestBody: RequestBody = .init(model: arguments.model, prompt: arguments.prompt)

        // Build URL
        guard let url = URL(string: "http://localhost:11434/api/generate") else {
            throw NSError(domain: "OllamaTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        // Build URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        // Execute network call
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        // Validate status code
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw NSError(domain: "OllamaTool", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(bodyString)"])
        }

        // Decode and return the `response` field
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let responseMessage = decoded.response
        print(responseMessage)
        return responseMessage
    }
}

