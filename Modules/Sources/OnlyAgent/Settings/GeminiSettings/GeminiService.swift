//
//  GeminiService.swift
//  Modules
//
//  Created by Bo Liu on 05.12.25.
//

import Dependencies
import DependenciesMacros
import FirebaseAILogic
import FirebaseCore
import Sharing

@DependencyClient
public struct GeminiService: Sendable {
    public var setAPIKey: @Sendable (String) -> Void
    public var models: @Sendable () -> [GeminiDataModel] = { [] }
    public var chat: @Sendable (_ model: String, _ prompt: String) async throws -> String = { _,_ in "" }
    public var test: @Sendable () async -> Bool = { true }
}

extension GeminiService: DependencyKey {
    public static let liveValue: Self = {
       let live = GeminiServiceLive()
        return .init(
            setAPIKey: live.setAPIKey,
            models: live.models,
            chat: live.chat,
            test: live.test
        )
    }()
    
    public static let testValue = Self()
}

extension DependencyValues {
    public var geminiService: GeminiService {
        get { self[GeminiService.self] }
        set { self[GeminiService.self] = newValue }
    }
}

private final class GeminiServiceLive: Sendable {
    private let ai = LockIsolated<FirebaseAI?>(nil)
    
    @Sendable
    func setAPIKey(_ key: String) {
        guard !key.isEmpty else {
            return
        }
        let options = FirebaseOptions.defaultOptions()
        options?.apiKey = key
        guard let options else { return }
        
        // Check if Firebase is already configured
        if FirebaseApp.app() == nil {
            FirebaseApp.configure(options: options)
        }
        
        guard let app = FirebaseApp.app() else { return }
        ai.setValue(FirebaseAI.firebaseAI(app: app))
    }
    
    @Sendable
    func models() -> [GeminiDataModel] {
        [
            "gemini-3-pro-preview",
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite"
        ]
            .map(GeminiDataModel.init)
    }
    
    @Sendable
    func chat(_ model: String, _ prompt: String) async throws -> String {
        @Shared(.geminiAPIKey) var apiKeyShared
        let apiKey: String = apiKeyShared
        if ai.value == nil && !apiKey.isEmpty {
            setAPIKey(apiKey)
        }
        guard let aiValue = ai.value else {
            throw GeminiError.uninitialized
        }
        
        let generativeModel = aiValue.generativeModel(modelName: model)
        let systemPrompt = "You are an AppleScript expert. You generate executable AppleScript code (NOT shell scripts) for macOS automation. Always use AppleScript syntax with 'tell application' commands. Never output shell scripts or bash commands directly."
        let fullPrompt = "\(systemPrompt)\n\n\(prompt)"
        
        let response = try await generativeModel.generateContent(fullPrompt)
        return response.text ?? ""
    }
    
    @Sendable
    func test() async -> Bool {
        @Shared(.geminiAPIKey) var apiKeyShared
        let apiKey: String = apiKeyShared
        if ai.value == nil && !apiKey.isEmpty {
            setAPIKey(apiKey)
        }
        guard let aiValue = ai.value else {
            return false
        }
        let model = aiValue.generativeModel(modelName: "gemini-2.5-flash-lite")
        let response = try? await model.generateContent("Hello")
        return response?.text != nil
    }
}

public enum GeminiError: Error {
    case uninitialized
}
