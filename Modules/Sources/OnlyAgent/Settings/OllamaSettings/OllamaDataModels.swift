//
//  OllamaTag.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Foundation

public struct OllamaModels: Codable {
    public let models: [OllamaTag]
}

public struct OllamaTag: Codable, Identifiable, Equatable, AIModel {
    public let model: String
    public let digest: String
    
    public var id: String {
        digest
    }
}

struct OllamaChatMessage: Codable, Sendable {
    let model: String
    let response: String
    let done: Bool
    let thinking: String?
}
