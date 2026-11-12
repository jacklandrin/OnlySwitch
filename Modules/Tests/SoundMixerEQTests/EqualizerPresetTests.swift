import Testing
@testable import SoundMixerEQ

struct EqualizerPresetTests {
    /// Raw values are a wire contract with OnlyRemote; keep in sync with `RemoteEqualizerPreset`.
    @Test func catalogIsStableAndOffersAtLeastEightPresets() {
        #expect(EqualizerPreset.allCases.map(\.rawValue) == [
            "flat", "pop", "rock", "jazz", "classical", "electronic", "hipHop", "vocal",
            "bassBoost", "trebleBoost", "acoustic", "loudness",
        ])
        #expect(EqualizerPreset.allCases.count >= 8)
    }

    @Test(arguments: EqualizerPreset.allCases)
    func everyCurveIsValidAndMatchesItself(preset: EqualizerPreset) {
        #expect(preset.gains.count == EqualizerSettings.frequencies.count)
        #expect(preset.gains.allSatisfy { (-12...12).contains($0) })
        #expect(preset.settings.gains == preset.gains)
        #expect(preset.settings.preset == preset)
        #expect(preset.settings.isFlat == (preset == .flat))
    }

    @Test func curvesAreDistinctAndCustomCurvesHaveNoPreset() {
        #expect(Set(EqualizerPreset.allCases.map(\.gains)).count == EqualizerPreset.allCases.count)
        #expect(EqualizerSettings.flat.preset == .flat)
        var custom = EqualizerPreset.rock.settings
        custom.setGain(custom.gains[0] - 1, band: 0)
        #expect(custom.preset == nil)
    }
}
