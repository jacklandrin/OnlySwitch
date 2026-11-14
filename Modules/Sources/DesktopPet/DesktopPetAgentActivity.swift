import Foundation

public enum DesktopPetAgent: String, CaseIterable, Equatable, Sendable {
    case codex
    case claude

    public var name: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }
}

public struct DesktopPetAgentEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case started
        case activity
        case completed
        case stopped
        case unavailable
    }

    public var agent: DesktopPetAgent
    public var sessionID: String
    public var turnID: String?
    public var id: String
    public var date: Date
    public var kind: Kind
    public var isHistorical: Bool

    public init(
        agent: DesktopPetAgent,
        sessionID: String,
        turnID: String? = nil,
        id: String,
        date: Date,
        kind: Kind,
        isHistorical: Bool = false
    ) {
        self.agent = agent
        self.sessionID = sessionID
        self.turnID = turnID
        self.id = id
        self.date = date
        self.kind = kind
        self.isHistorical = isHistorical
    }
}

public struct DesktopPetAgentUpdate: Equatable, Sendable {
    public var events: [DesktopPetAgentEvent]
    public var date: Date

    public init(events: [DesktopPetAgentEvent], date: Date) {
        self.events = events
        self.date = date
    }
}

public struct DesktopPetAgentCompletion: Equatable, Sendable, Identifiable {
    public var id: String
    public var agent: DesktopPetAgent
}
