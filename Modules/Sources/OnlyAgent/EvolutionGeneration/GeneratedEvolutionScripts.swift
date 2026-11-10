//
//  GeneratedEvolutionScripts.swift
//  Modules
//

import Foundation

/// What kind of Evolution the scripts are generated for.
public enum EvolutionScriptTarget: String, Sendable, Equatable {
    case switchControl = "switch"
    case button
}

public struct GeneratedScript: Equatable, Sendable {
    public var kind: AgentScriptKind
    public var code: String

    public init(kind: AgentScriptKind, code: String) {
        self.kind = kind
        self.code = code
    }
}

/// Scripts a model wrote for an Evolution. They are only placed in the
/// editor; nothing here is ever run without the user's action.
public struct GeneratedEvolutionScripts: Equatable, Sendable {
    public var name: String?
    public var turnOn: GeneratedScript?
    public var turnOff: GeneratedScript?
    public var status: GeneratedScript?
    /// The trimmed output of `status` when the switch is on.
    public var statusOnOutput: String?
    public var button: GeneratedScript?
    public var notes: String?

    public init(
        name: String? = nil,
        turnOn: GeneratedScript? = nil,
        turnOff: GeneratedScript? = nil,
        status: GeneratedScript? = nil,
        statusOnOutput: String? = nil,
        button: GeneratedScript? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.turnOn = turnOn
        self.turnOff = turnOff
        self.status = status
        self.statusOnOutput = statusOnOutput
        self.button = button
        self.notes = notes
    }
}

public enum EvolutionScriptGenerationError: Error, Equatable, Sendable {
    case noModelSelected
    case emptyReply
    case unparseable
    case incomplete
    case declined(String)
    case failed(String)
}

extension EvolutionScriptGenerationError {
    /// A value-free label that is safe to log.
    var category: String {
        switch self {
        case .noModelSelected: "noModelSelected"
        case .emptyReply: "emptyReply"
        case .unparseable: "unparseable"
        case .incomplete: "incomplete"
        case .declined: "declined"
        case .failed: "failed"
        }
    }
}
