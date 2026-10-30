import Foundation

public struct RemoteBrightnessDisplay: Codable, Equatable, Identifiable, Sendable {
    public enum Control: String, Codable, Equatable, Sendable {
        case native, ddc, software, unavailable
    }

    public let id: UInt32
    public let name: String
    public let control: Control
    /// 0...1, the user-facing level (combined hardware + software dimming).
    public let level: Double
    public let hasError: Bool

    public init(id: UInt32, name: String, control: Control, level: Double, hasError: Bool) {
        self.id = id
        self.name = String(name.prefix(120))
        self.control = control
        self.level = level.isFinite ? min(1, max(0, level)) : 1
        self.hasError = hasError
    }

    /// Unknown controls decode as `.unavailable` so a newer Mac never breaks an older client.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UInt32.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            control: (try? container.decode(Control.self, forKey: .control)) ?? .unavailable,
            level: try container.decode(Double.self, forKey: .level),
            hasError: try container.decodeIfPresent(Bool.self, forKey: .hasError) ?? false
        )
    }
}

public struct RemoteBrightnessSnapshot: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let displays: [RemoteBrightnessDisplay]

    public init(revision: UInt64, displays: [RemoteBrightnessDisplay]) {
        self.revision = revision
        self.displays = Array(displays.prefix(16))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            revision: try container.decode(UInt64.self, forKey: .revision),
            displays: try container.decode([RemoteBrightnessDisplay].self, forKey: .displays)
        )
    }
}

public enum RemoteBrightnessCommand: Codable, Equatable, Sendable {
    case setLevel(displayID: UInt32, level: Double)
}
