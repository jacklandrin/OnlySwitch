import Foundation
import Testing
@testable import SoundMixerEQ

struct EqualizerSettingsTests {
    @Test func normalizesMalformedValues() {
        let settings = EqualizerSettings(gains: [.nan, .infinity, -99, 99])
        #expect(settings.gains == [0, 0, -12, 12, 0, 0, 0, 0, 0, 0])
        #expect(EqualizerSettings(gains: Array(repeating: 3, count: 20)).gains.count == 10)
        #expect(EqualizerSettings.flat.isFlat)
    }

    @Test func invalidBandsCannotChangeSettings() {
        var settings = EqualizerSettings.flat
        settings.setGain(8, band: -1)
        settings.setGain(8, band: 10)
        #expect(settings == .flat)
        settings.setGain(99, band: 5)
        #expect(settings.gains[5] == 12)
        settings.setGain(.nan, band: 5)
        #expect(settings == .flat)
    }

    @Test func decodingAlsoValidatesStoredValues() throws {
        let settings = try JSONDecoder().decode(EqualizerSettings.self, from: Data(#"{"gains":[99,-99,3]}"#.utf8))
        #expect(settings.gains == [12, -12, 3, 0, 0, 0, 0, 0, 0, 0])
        #expect(try JSONDecoder().decode(EqualizerSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }
}
