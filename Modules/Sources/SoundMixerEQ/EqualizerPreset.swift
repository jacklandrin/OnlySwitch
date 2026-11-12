import Foundation

/// Built-in EQ curves. The raw value is a stable wire and persistence identifier.
/// The active preset is derived from the stored gains, so persisted settings stay gain-only.
public enum EqualizerPreset: String, CaseIterable, Identifiable, Sendable {
    case flat, pop, rock, jazz
    case classical, electronic, hipHop, vocal
    case bassBoost, trebleBoost, acoustic, loudness

    public var id: String { rawValue }

    /// Localization key for the preset's display name.
    public var titleKey: String {
        switch self {
        case .flat: "Flat"
        case .pop: "Pop"
        case .rock: "Rock"
        case .jazz: "Jazz"
        case .classical: "Classical"
        case .electronic: "Electronic"
        case .hipHop: "Hip-Hop"
        case .vocal: "Vocal"
        case .bassBoost: "Bass Boost"
        case .trebleBoost: "Treble Boost"
        case .acoustic: "Acoustic"
        case .loudness: "Loudness"
        }
    }

    /// Gains for 31.25 Hz … 16 kHz, matching `EqualizerSettings.frequencies`.
    public var gains: [Double] {
        switch self {
        case .flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .pop: [-1, 0, 2, 4, 5, 4, 2, 0, -1, -1]
        case .rock: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]
        case .jazz: [4, 3, 1, 2, -1, -1, 0, 1, 3, 4]
        case .classical: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]
        case .electronic: [5, 4, 1, 0, -2, 2, 1, 2, 4, 5]
        case .hipHop: [5, 4, 2, 3, -1, -1, 1, -1, 2, 3]
        case .vocal: [-2, -3, -3, 1, 4, 4, 3, 1, 0, -2]
        case .bassBoost: [6, 5, 4, 2, 1, 0, 0, 0, 0, 0]
        case .trebleBoost: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .acoustic: [4, 4, 3, 1, 2, 2, 3, 3, 3, 2]
        case .loudness: [6, 4, 0, 0, -2, 0, -1, -4, 5, 1]
        }
    }

    public var settings: EqualizerSettings { EqualizerSettings(gains: gains) }

    /// The preset whose curve exactly matches `settings`, or `nil` for a custom curve.
    public init?(matching settings: EqualizerSettings) {
        guard let preset = Self.allCases.first(where: { $0.settings == settings }) else { return nil }
        self = preset
    }
}

public extension EqualizerSettings {
    var preset: EqualizerPreset? { EqualizerPreset(matching: self) }
}
