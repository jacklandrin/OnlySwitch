import SwiftUI

/// Mirrors the Mac's `EqualizerPreset` raw values; the Mac owns the gain curves.
/// Unknown identifiers from a newer Mac are shown as a custom curve.
enum RemoteEqualizerPreset: String, CaseIterable, Identifiable, Sendable {
    case flat, pop, rock, jazz
    case classical, electronic, hipHop, vocal
    case bassBoost, trebleBoost, acoustic, loudness

    var id: String { rawValue }

    var title: LocalizedStringKey {
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
}
