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

final class GeminiLive: Sendable {
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
    func models() -> [ProviderModel] {
        [
            "gemini-3-pro-preview",
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
        if ai.value == nil && !apiKey.isEmpty {
            setAPIKey(apiKey)
        }
        guard let aiValue = ai.value else {
            throw GeminiError.uninitialized
        }
        let systemPrompt = "You are an AppleScript expert. You generate executable AppleScript code (NOT shell scripts) for macOS automation. Always use AppleScript syntax with 'tell application' commands. Never output shell scripts or bash commands directly."
        let modelContent = ModelContent(role: "system", parts: TextPart(systemPrompt))
        
        let generativeModel = aiValue.generativeModel(modelName: model, systemInstruction: modelContent)
                
        let response = try await generativeModel.generateContent(prompt)
        return response.text ?? ""
    }
    
    @Sendable
    func test() async -> Bool {
        @Shared(.geminiAPIKey) var apiKeyShared: String = ""
        let apiKey: String = apiKeyShared
        if ai.value == nil && !apiKey.isEmpty {
            setAPIKey(apiKey)
        }
        guard let aiValue = ai.value else {
            return false
        }
        let model = aiValue.generativeModel(modelName: "gemini-3-pro-preview")
        let response = try? await model.generateContent("Hello")
        return response?.text != nil
    }
}

public enum GeminiError: Error {
    case uninitialized
}
