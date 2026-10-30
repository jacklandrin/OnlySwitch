import Foundation

public struct RemoteSoundMixerOutput: Codable, Equatable, Sendable {
    public let name: String
    public let symbolName: String

    public init(name: String, symbolName: String) {
        self.name = String(name.prefix(120))
        self.symbolName = String(symbolName.prefix(120))
    }
}

public struct RemoteSoundMixerEqualizer: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case flat, pending, waitingForAudio, active, unavailable, unsupported
    }

    public static let bandCount = 10
    public static let frequencies: [Double] = [31.25, 62.5, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    public let gains: [Double]
    public let status: Status

    public init(gains: [Double], status: Status) {
        self.gains = (0..<Self.bandCount).map { gains.indices.contains($0) ? Self.clampGain(gains[$0]) : 0 }
        self.status = status
    }

    public static func clampGain(_ value: Double) -> Double { value.isFinite ? min(12, max(-12, value)) : 0 }

    /// Unknown statuses decode as `.unavailable` so a newer Mac never breaks an older client.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            gains: try container.decodeIfPresent([Double].self, forKey: .gains) ?? [],
            status: (try? container.decode(Status.self, forKey: .status)) ?? .unavailable
        )
    }
}

public struct RemoteSoundMixerRouting: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case followingSystem, pending, waitingForDevices, partial, active, unsupported, unavailable
    }

    /// Empty means "follow the system output".
    public let selectedDeviceIDs: [String]
    public let status: Status

    public init(selectedDeviceIDs: [String], status: Status) {
        self.selectedDeviceIDs = Array(selectedDeviceIDs.map { String($0.prefix(256)) }.prefix(16))
        self.status = status
    }

    /// Unknown statuses decode as `.unavailable` so a newer Mac never breaks an older client.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedDeviceIDs: try container.decodeIfPresent([String].self, forKey: .selectedDeviceIDs) ?? [],
            status: (try? container.decode(Status.self, forKey: .status)) ?? .unavailable
        )
    }
}

public struct RemoteSoundMixerOutputDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = String(id.prefix(256))
        self.name = String(name.prefix(120))
        self.isDefault = isDefault
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            isDefault: try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        )
    }
}

public struct RemoteSoundMixerApp: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let volume: Double
    public let isMuted: Bool
    /// `nil` when the peer predates protocol 1.8 or the app has no equalizer state.
    public let equalizer: RemoteSoundMixerEqualizer?
    /// `nil` when the peer predates protocol 1.8 or the app has no routing state.
    public let routing: RemoteSoundMixerRouting?

    public init(
        id: String,
        name: String,
        volume: Double,
        isMuted: Bool,
        equalizer: RemoteSoundMixerEqualizer? = nil,
        routing: RemoteSoundMixerRouting? = nil
    ) {
        self.id = String(id.prefix(256))
        self.name = String(name.prefix(120))
        self.volume = Self.clampVolume(volume)
        self.isMuted = isMuted
        self.equalizer = equalizer
        self.routing = routing
    }

    public static func clampVolume(_ value: Double) -> Double { min(100, max(0, value.isFinite ? value : 0)) }
}

public struct RemoteSoundMixerSnapshot: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let isEnabled: Bool
    public let systemVolume: Double
    public let output: RemoteSoundMixerOutput?
    public let apps: [RemoteSoundMixerApp]
    public let isSystemVolumeAvailable: Bool
    public let outputDevices: [RemoteSoundMixerOutputDevice]

    public init(
        revision: UInt64,
        isEnabled: Bool,
        systemVolume: Double,
        output: RemoteSoundMixerOutput?,
        apps: [RemoteSoundMixerApp],
        isSystemVolumeAvailable: Bool = true,
        outputDevices: [RemoteSoundMixerOutputDevice] = []
    ) {
        self.revision = revision
        self.isEnabled = isEnabled
        self.systemVolume = RemoteSoundMixerApp.clampVolume(systemVolume)
        self.output = output
        self.apps = Array(apps.prefix(64))
        self.isSystemVolumeAvailable = isSystemVolumeAvailable
        self.outputDevices = Array(outputDevices.prefix(32))
    }

    /// Keys added in protocol 1.8 are optional so legacy snapshots still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            revision: try container.decode(UInt64.self, forKey: .revision),
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            systemVolume: try container.decode(Double.self, forKey: .systemVolume),
            output: try container.decodeIfPresent(RemoteSoundMixerOutput.self, forKey: .output),
            apps: try container.decode([RemoteSoundMixerApp].self, forKey: .apps),
            isSystemVolumeAvailable: try container.decodeIfPresent(Bool.self, forKey: .isSystemVolumeAvailable) ?? true,
            outputDevices: try container.decodeIfPresent([RemoteSoundMixerOutputDevice].self, forKey: .outputDevices) ?? []
        )
    }

    /// Compares every field except `revision`, so unchanged state is not re-sent.
    public func hasSameContent(as other: Self) -> Bool {
        isEnabled == other.isEnabled
            && systemVolume == other.systemVolume
            && output == other.output
            && apps == other.apps
            && isSystemVolumeAvailable == other.isSystemVolumeAvailable
            && outputDevices == other.outputDevices
    }
}

public enum RemoteSoundMixerCommand: Codable, Equatable, Sendable {
    case setSystemVolume(Double)
    case setAppVolume(id: String, volume: Double)
    case setAppMuted(id: String, isMuted: Bool)
    case setAppEqualizerGain(id: String, band: Int, gain: Double)
    case resetAppEqualizer(id: String)
    case toggleAppOutputDevice(id: String, deviceID: String)
    case followSystemOutput(id: String)

    /// Commands that are only valid once both peers negotiated `supportsSoundMixerTabRemote`.
    public var requiresSoundMixerTab: Bool {
        switch self {
        case .setSystemVolume, .setAppVolume, .setAppMuted: false
        case .setAppEqualizerGain, .resetAppEqualizer, .toggleAppOutputDevice, .followSystemOutput: true
        }
    }
}
