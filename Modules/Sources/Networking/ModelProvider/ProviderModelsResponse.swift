//
//  ProviderModelsResponse.swift
//  Modules
//
//  Created by Codex on 28.03.26.
//

import Foundation

public enum RemoteModelProviderKey: String, Sendable {
    case openai
    case codex
    case gemini
    case claude
}

struct ProviderModelsResponse: Decodable {
    let models: [ProviderModelGroup]

    func models(for provider: RemoteModelProviderKey) -> [String] {
        models
            .filter { $0.normalizedProvider == provider }
            .flatMap(\.items)
    }
}

struct ProviderModelGroup: Decodable {
    let provider: String
    let family: String
    let items: [String]

    var normalizedProvider: RemoteModelProviderKey? {
        let provider = provider.lowercased()
        let family = family.lowercased()

        switch (provider, family) {
            case ("openai", "gpt"):
                return .openai
            case ("openai", "codex"):
                return .codex
            case ("google", "gemini"), ("gemini", "gemini"):
                return .gemini
            case ("anthropic", "claude"):
                return .claude
            default:
                return nil
        }
    }
}
