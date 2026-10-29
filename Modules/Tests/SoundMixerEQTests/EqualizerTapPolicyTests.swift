import Testing
@testable import SoundMixerEQ

struct EqualizerTapPolicyTests {
    @Test func explicitRouteRetainsAFullVolumeFlatTap() {
        #expect(EqualizerTapPolicy.requiresTap(gain: 1, settings: .flat, hasExplicitRoute: true))
        #expect(EqualizerTapPolicy.requiresTap(gain: 1, settings: .flat, hasExplicitRoute: false) == false)
    }

    @Test func fullVolumeOnlyBypassesFlatEQ() {
        #expect(EqualizerTapPolicy.requiresTap(gain: 1, settings: .flat) == false)
        #expect(EqualizerTapPolicy.requiresTap(gain: 0.5, settings: .flat))
        #expect(EqualizerTapPolicy.requiresTap(gain: 0, settings: .flat))
        var settings = EqualizerSettings.flat
        settings.setGain(-6, band: 5)
        #expect(EqualizerTapPolicy.requiresTap(gain: 1, settings: settings))
    }

    @Test func processOrderingDoesNotRebuildButSourceChangesDo() {
        #expect(EqualizerTapPolicy.requiresRebuild(previousProcessIDs: [1, 2], previousOutputUID: "speakers", processIDs: [2, 1], outputUID: "speakers") == false)
        #expect(EqualizerTapPolicy.requiresRebuild(previousProcessIDs: [1, 2], previousOutputUID: "speakers", processIDs: [1, 2, 3], outputUID: "speakers"))
        #expect(EqualizerTapPolicy.requiresRebuild(previousProcessIDs: [1, 2], previousOutputUID: "speakers", processIDs: [1], outputUID: "speakers"))
        #expect(EqualizerTapPolicy.requiresRebuild(previousProcessIDs: [1, 2], previousOutputUID: "speakers", processIDs: [1, 2], outputUID: "headphones"))
    }
}
