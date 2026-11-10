//
//  AgentEvolutionClient.swift
//  Modules
//

import Dependencies
import DependenciesMacros

public struct AgentEvolutionDraft: Equatable, Sendable {
    public var name: String
    public var command: String

    public init(name: String, command: String) {
        self.name = name
        self.command = command
    }
}

/// Saves an agent plan as an Evolution button.
///
/// Evolution persistence lives in `AppFeature`, which `OnlyAgent` must not
/// import, so the app injects the live implementation.
@DependencyClient
public struct AgentEvolutionClient: Sendable {
    public var saveButton: @Sendable (AgentEvolutionDraft) async throws -> Void
    /// Installs a persistent `SUDO_ASKPASS` helper for saved buttons whose
    /// shell steps need administrator rights, returning its path.
    public var installAskpass: @Sendable () async throws -> String?
}

extension AgentEvolutionClient: DependencyKey {
    public static let liveValue = Self()
    public static let testValue = Self()
}

extension DependencyValues {
    public var agentEvolutionClient: AgentEvolutionClient {
        get { self[AgentEvolutionClient.self] }
        set { self[AgentEvolutionClient.self] = newValue }
    }
}
