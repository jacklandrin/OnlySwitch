//
//  ModelProviderService.swift
//  Modules
//
//  Created by Bo Liu on 13.12.25.
//

import Dependencies
import DependenciesMacros

@DependencyClient
public struct ModelProviderService: Sendable {
    public var setAPIKey: @Sendable (ModelProvider, String, String) -> Void
    public var models: @Sendable (ModelProvider) async throws -> [ProviderModel] = { _ in [] }
    public var chat: @Sendable (ModelProvider, _ model: String, _ prompt: String) async throws -> String = { _,_,_ in "" }
    public var test: @Sendable (ModelProvider) async -> Bool = { _ in true }
}

@available(macOS 26.0, *)
extension ModelProviderService: DependencyKey {
    static public var liveValue: Self = {
        let ollamaClient = OllamaLive()
        let openAIClient = OpenAILive()
        let geminiClient = GeminiLive()
        
        return .init { provider, apiKey, host in
            switch provider {
                case .openai:
                    openAIClient.setAPIToken(apiKey, host: host)
                case .gemini:
                    geminiClient.setAPIKey(apiKey)
                default:
                    break
            }
        } models: { provider in
            switch provider {
                case .ollama:
                    return try await ollamaClient.models()
                case .openai:
                    return openAIClient.models()
                case .gemini:
                    return geminiClient.models()
            }
        } chat: { provider, model, prompt in
            switch provider {
                case .ollama:
                    return try await ollamaClient.chat(model, prompt)
                case .openai:
                    return try await openAIClient.chat(model, prompt)
                case .gemini:
                    return try await geminiClient.chat(model, prompt)
            }
        } test: { provider in
            switch provider {
                case .ollama:
                    return true
                case .openai:
                    return await openAIClient.test()
                case .gemini:
                    return await geminiClient.test()
            }
        }
    }()
    
    static public var testValue = Self()
}

@available(macOS 26.0, *)
extension DependencyValues {
    public var modelProviderService: ModelProviderService {
        get { self[ModelProviderService.self] }
        set { self[ModelProviderService.self] = newValue }
    }
}
