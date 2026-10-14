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

public struct ProviderModelsCatalog: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let models: [ProviderModelGroup]

    public init(updatedAt: String, models: [ProviderModelGroup]) {
        self.updatedAt = updatedAt; self.models = models
    }

    public static func resolve(remote: Self?, bundled: Self?) -> Self {
        guard let remote else {
            guard let bundled else { return Self(updatedAt: "", models: []) }
            return bundled
        }
        guard let bundled else { return remote }
        var groups = remote.models
        for local in bundled.models {
            if let index = groups.firstIndex(where: { $0.provider.lowercased() == local.provider.lowercased() && $0.family.lowercased() == local.family.lowercased() }) {
                groups[index] = ProviderModelGroup(provider: groups[index].provider, family: groups[index].family, items: unique(local.items + groups[index].items))
            } else { groups.append(local) }
        }
        return Self(updatedAt: max(remote.updatedAt, bundled.updatedAt), models: groups)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>(); return values.filter { seen.insert($0).inserted }
    }

    public func models(for provider: RemoteModelProviderKey) -> [String] {
        models
            .filter { $0.normalizedProvider == provider }
            .flatMap(\.items)
    }
}

public struct ProviderModelGroup: Codable, Equatable, Sendable {
    public let provider: String
    public let family: String
    public let items: [String]

    public init(provider: String, family: String, items: [String]) {
        self.provider = provider; self.family = family; self.items = items
    }

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

typealias ProviderModelsResponse = ProviderModelsCatalog
