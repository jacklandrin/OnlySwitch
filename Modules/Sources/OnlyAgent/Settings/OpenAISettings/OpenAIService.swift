//
//  OpenAIService.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import Dependencies
import DependenciesMacros
import OpenAI
import Foundation
import Sharing

public enum OpenAIError: Error {
    case uninitialized
}

final class OpenAILive: Sendable {
    private let openAI = LockIsolated<OpenAI?>(nil)
    
    @Sendable
    func setAPIToken(_ apiToken: String, host: String = "api.openai.com") {
        guard !apiToken.isEmpty else {
            return
        }
        openAI.setValue(OpenAI(configuration: .init(token: apiToken, host: host)))
    }
    
    @Sendable
    func models() -> [ProviderModel] {
        Model.allModels(satisfying: .init(supportedEndpoints: [.chatCompletions])).map { .init(model: $0) }
    }
    
    @Sendable
    func chat(_ model: String, _ prompt: String) async throws -> String {
        @Shared(.openAIAPIKey) var apiKeyShared: String = ""
        @Shared(.openAIHost) var hostShared
        let apiKey: String = apiKeyShared
        let host: String = hostShared
        if openAI.value == nil {
            openAI.setValue(OpenAI(configuration: .init(token: apiKey, host: host)))
        }
        guard let openAI = openAI.value else {
            throw OpenAIError.uninitialized
        }
        let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: "You are an AppleScript expert. You generate executable AppleScript code (NOT shell scripts) for macOS automation. Always use AppleScript syntax with 'tell application' commands. Never output shell scripts or bash commands directly.")
        let userMessage = ChatQuery.ChatCompletionMessageParam(role: .user, content: prompt)
        guard let systemMessage, let userMessage else {
            return ""
        }
        
        let result = try await openAI.chats(
            query: .init(
                messages: [
                    systemMessage,
                    userMessage
                ],
                model: model
            )
        )
        
        return result.choices.first?.message.content ?? ""
    }
    
    @Sendable
    func test() async -> Bool {
        let models = try? await openAI.value?.models()
        return models != nil
    }
}
