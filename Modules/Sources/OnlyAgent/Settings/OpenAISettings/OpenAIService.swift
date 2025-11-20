//
//  OpenAIService.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import Dependencies
import DependenciesMacros
import OpenAI

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
        let systemMessage = ChatQuery.ChatCompletionMessageParam(role: .system, content: "You are a helpful AI assistant for generating apple scripts. Here is your first question:")
        let userMessage = ChatQuery.ChatCompletionMessageParam(role: .user, content: prompt)
        guard let systemMessage, let userMessage else {
            return ""
        }
        
        let result = try await openAI.value?.chats(
            query: .init(
                messages: [
                    systemMessage,
                    userMessage
                ],
                model: model
            )
        )
        
        return result?.choices.first?.message.content ?? ""
    }
    
    @Sendable
    func test() async -> Bool {
        let models = try? await openAI.value?.models()
        return models != nil
    }
}
