import Foundation

public struct RemoteSoundMixerOutput: Codable, Equatable, Sendable {
    public let name: String
    public let symbolName: String

    public init(name: String, symbolName: String) {
        self.name = String(name.prefix(120))
        self.symbolName = String(symbolName.prefix(120))
    }
}

public struct RemoteSoundMixerApp: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let volume: Double
    public let isMuted: Bool

    public init(id: String, name: String, volume: Double, isMuted: Bool) {
        self.id = String(id.prefix(256))
        self.name = String(name.prefix(120))
        self.volume = Self.clamp(volume)
        self.isMuted = isMuted
    }

    static func clamp(_ value: Double) -> Double { min(100, max(0, value.isFinite ? value : 0)) }
}

public struct RemoteSoundMixerSnapshot: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let isEnabled: Bool
    public let systemVolume: Double
    public let output: RemoteSoundMixerOutput?
    public let apps: [RemoteSoundMixerApp]

    public init(revision: UInt64, isEnabled: Bool, systemVolume: Double, output: RemoteSoundMixerOutput?, apps: [RemoteSoundMixerApp]) {
        self.revision = revision
        self.isEnabled = isEnabled
        self.systemVolume = RemoteSoundMixerApp.clamp(systemVolume)
        self.output = output
        self.apps = Array(apps.prefix(64))
    }
}

public enum RemoteSoundMixerCommand: Codable, Equatable, Sendable {
    case setSystemVolume(Double)
    case setAppVolume(id: String, volume: Double)
    case setAppMuted(id: String, isMuted: Bool)
}
