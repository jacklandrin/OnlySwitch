//
//  AgentPasswordModels.swift
//  Modules
//

import Foundation

/// `sudo` asked for a password while a step was running.
public struct AgentPasswordRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The prompt sudo passed to the askpass helper, e.g. "Password:".
    public let prompt: String

    public init(id: UUID, prompt: String) {
        self.id = id
        self.prompt = prompt
    }
}

/// Events produced while a step runs.
public enum AgentRunEvent: Equatable, Sendable {
    case passwordRequested(AgentPasswordRequest)
    case finished(String)
}
