/// Volume key behaviour on a `0...100` scale, matching macOS: 16 steps, or 64 with Shift+Option.
public struct DisplayVolumeLevel: Equatable, Sendable {
    public var volume: Double
    public var volumeBeforeMute: Double

    /// Devices store whole percents; a value within half a percent of a step counts as on it,
    /// so a rounded read-back never stalls the next step.
    private static let tolerance = 0.5

    public init(volume: Double, volumeBeforeMute: Double = 50) {
        self.volume = volume
        self.volumeBeforeMute = volumeBeforeMute
    }

    public var isMuted: Bool { volume == 0 }

    public mutating func apply(_ key: VolumeKeyEvent.Key, fine: Bool) {
        let step = 100.0 / (fine ? 64 : 16)
        let slack = Self.tolerance / step
        switch key {
        case .volumeUp:
            volume = min(100, ((volume / step + slack).rounded(.down) + 1) * step)
        case .volumeDown:
            volume = max(0, ((volume / step - slack).rounded(.up) - 1) * step)
        case .mute:
            if volume > 0 {
                volumeBeforeMute = volume
                volume = 0
            } else {
                volume = volumeBeforeMute > 0 ? volumeBeforeMute : 50
            }
        }
    }
}
