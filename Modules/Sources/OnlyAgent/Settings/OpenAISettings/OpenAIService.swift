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

@DependencyClient
public struct OpenAIService: Sendable {
    public var setAPIToken: @Sendable (String, String) -> Void = { _,_ in }
    public var models: @Sendable () -> [OpenAIDataModel] = { [] }
    public var chat: @Sendable (_ model: String, _ prompt: String) async throws -> String = { _,_ in "" }
    public var test: @Sendable () async -> Bool = { true }
}

extension OpenAIService: DependencyKey {
    public static let liveValue: Self = {
       let client = OpenAILive()
        return .init(
            setAPIToken: client.setAPIToken,
            models: client.models,
            chat: client.chat,
            test: client.test
        )
    }()
    
    public static let testValue = Self()
}

extension DependencyValues {
    public var openAIService: OpenAIService {
        get { self[OpenAIService.self] }
        set { self[OpenAIService.self] = newValue }
    }
}

private final class OpenAILive: Sendable {
    private let openAI = LockIsolated<OpenAI?>(nil)
    
    @Sendable
    func setAPIToken(_ apiToken: String, host: String = "api.openai.com") {
        guard !apiToken.isEmpty else {
            return
        }
        openAI.setValue(OpenAI(configuration: .init(token: apiToken, host: host)))
    }
    
    @Sendable
    func models() -> [OpenAIDataModel] {
        Model.allModels(satisfying: .init(supportedEndpoints: [.chatCompletions])).map { .init(model: $0) }
    }
    
    @Sendable
    func chat(_ model: String, _ prompt: String) async throws -> String {
        @Shared(.openAIAPIKey) var apiKeyShared
        @Shared(.openAIHost) var hostShared
        let apiKey: String = apiKeyShared
        let host: String = hostShared
        if openAI.value == nil {
            openAI.setValue(OpenAI(configuration: .init(token: apiKey, host: host)))
        }
        guard let openAI = openAI.value else {
            throw OpenAIError.uninitialized
        }
        let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: "You can generate an executable apple script command in macOS for a specific purpose. ")
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
