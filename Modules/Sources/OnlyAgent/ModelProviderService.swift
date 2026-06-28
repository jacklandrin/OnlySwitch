//
//  ModelProviderService.swift
//  Modules
//
//  Created by Bo Liu on 13.12.25.
//

import Dependencies
import DependenciesMacros
import CodexKit
import Networking

@DependencyClient
public struct ModelProviderService: Sendable {
    public var setAPIKey: @Sendable (ModelProvider, String, String) -> Void
    public var models: @Sendable (ModelProvider) async throws -> [ProviderModel] = { _ in [] }
    public var chatStream: @Sendable (
        ModelProvider,
        _ model: String,
        _ prompt: String
    ) async throws -> AsyncThrowingStream<ModelStreamEvent, Error> = { _, _, _ in
        AsyncThrowingStream { continuation in
            continuation.yield(.completed(finalText: ""))
            continuation.finish()
        }
    }
    public var chat: @Sendable (ModelProvider, _ model: String, _ prompt: String) async throws -> String = { _,_,_ in "" }
    public var test: @Sendable (ModelProvider) async -> Bool = { _ in true }
    public var codexSignIn: @Sendable () async throws -> ChatGPTSession = {
        throw CodexError.uninitialized
    }
    public var codexSignOut: @Sendable () async throws -> Void = {}
    public var codexCurrentSession: @Sendable () async -> ChatGPTSession? = { nil }
}

@available(macOS 26.0, *)
extension ModelProviderService: DependencyKey {
    static public var liveValue: Self {
        let ollamaClient = OllamaLive()
        let openAIClient = OpenAILive()
        let codexClient = CodexLive()
        let geminiClient = GeminiLive()
        let claudeClient = ClaudeLive()
        let providerModelsRemoteService = ProviderModelsRemoteService()
        
        return .init { provider, apiKey, host in
            switch provider {
                case .ollama:
                    ollamaClient.setHost(host: host)
                case .openai:
                    openAIClient.setAPIToken(apiKey, host: host)
                case .codex:
                    break
                case .gemini:
                    geminiClient.setAPIKey(apiKey)
                case .claude:
                    claudeClient.setAPIKey(apiKey)
            }
        } models: { provider in
            switch provider {
                case .ollama:
                    return try await ollamaClient.models()
                case .openai:
                    return try await providerModelsRemoteService.models(for: .openai).map(ProviderModel.init(model:))
                case .codex:
                    return try await providerModelsRemoteService.models(for: .codex).map(ProviderModel.init(model:))
                case .gemini:
                    return try await providerModelsRemoteService.models(for: .gemini).map(ProviderModel.init(model:))
                case .claude:
                    return try await providerModelsRemoteService.models(for: .claude).map(ProviderModel.init(model:))
            }
        } chatStream: { provider, model, prompt in
            switch provider {
                case .ollama:
                    return try await ollamaClient.chatStream(model, prompt)
                case .openai:
                    return try await openAIClient.chatStream(model, prompt)
                case .codex:
                    return try await codexClient.chatStream(model, prompt)
                case .gemini:
                    return try await geminiClient.chatStream(model, prompt)
                case .claude:
                    return try await claudeClient.chatStream(model, prompt)
            }
        } chat: { provider, model, prompt in
            let stream: AsyncThrowingStream<ModelStreamEvent, Error>
            switch provider {
                case .ollama:
                    stream = try await ollamaClient.chatStream(model, prompt)
                case .openai:
                    stream = try await openAIClient.chatStream(model, prompt)
                case .codex:
                    stream = try await codexClient.chatStream(model, prompt)
                case .gemini:
                    stream = try await geminiClient.chatStream(model, prompt)
                case .claude:
                    stream = try await claudeClient.chatStream(model, prompt)
            }
            
            var accumulatedContent = ""
            for try await event in stream {
                switch event {
                case let .contentDelta(delta):
                    accumulatedContent += delta
                case let .completed(finalText):
                    return finalText.isEmpty ? accumulatedContent : finalText
                case .thinkingDelta:
                    break
                }
            }
            return accumulatedContent
        } test: { provider in
            switch provider {
                case .ollama:
                    return true
                case .openai:
                    return await openAIClient.test()
                case .codex:
                    return await codexClient.test()
                case .gemini:
                    return await geminiClient.test()
                case .claude:
                    return await claudeClient.test()
            }
        } codexSignIn: {
            try await codexClient.signIn()
        } codexSignOut: {
            try await codexClient.signOut()
        } codexCurrentSession: {
            await codexClient.currentSession()
        }
    }
    
    static public var testValue: Self { Self() }
}

@available(macOS 26.0, *)
extension DependencyValues {
    public var modelProviderService: ModelProviderService {
        get { self[ModelProviderService.self] }
        set { self[ModelProviderService.self] = newValue }
    }
}
