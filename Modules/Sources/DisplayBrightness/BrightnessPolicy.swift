public enum BrightnessPolicy {
    public static func output(level: Double, control: BrightnessControl,
                              settings: BrightnessSettings) -> BrightnessOutput {
        let level = level.isFinite ? max(0, min(1, level)) : 1
        let floor = settings.allowZeroSoftwareBrightness ? 0.0 : 0.1
        switch control {
        case .native: return .init(hardware: level, software: 1)
        case .ddc where settings.combinedDimming:
            return .init(hardware: max(0, (level - 0.2) / 0.8),
                         software: level < 0.2 ? max(floor, level / 0.2) : 1)
        case .ddc: return .init(hardware: level, software: 1)
        case .software: return .init(hardware: nil, software: max(floor, level))
        case .unavailable: return .init(hardware: nil, software: 1)
        }
    }

    public static func level(hardware: Double, control: BrightnessControl,
                             settings: BrightnessSettings) -> Double {
        let value = hardware.isFinite ? max(0, min(1, hardware)) : 1
        return control == .ddc && settings.combinedDimming ? 0.2 + 0.8 * value : value
    }
}
