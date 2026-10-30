import Testing
@testable import DisplayBrightness

struct BrightnessPolicyTests {
    @Test func combinedRangeMeetsWithoutJump() {
        let settings = BrightnessSettings()
        #expect(BrightnessPolicy.output(level: 0.2, control: .ddc, settings: settings) == BrightnessOutput(hardware: 0, software: 1))
        #expect(BrightnessPolicy.output(level: 1, control: .ddc, settings: settings) == BrightnessOutput(hardware: 1, software: 1))
    }
    @Test func zeroRequiresExplicitOptIn() {
        var settings = BrightnessSettings()
        #expect(BrightnessPolicy.output(level: 0, control: .software, settings: settings).software == 0.1)
        #expect(BrightnessPolicy.output(level: 0, control: .ddc, settings: settings).software == 0.1)
        settings.allowZeroSoftwareBrightness = true
        #expect(BrightnessPolicy.output(level: 0, control: .software, settings: settings).software == 0)
    }
    @Test func hardwareOnlyAndNativeNeverShade() {
        var settings = BrightnessSettings(); settings.combinedDimming = false
        #expect(BrightnessPolicy.output(level: 0, control: .ddc, settings: settings) == BrightnessOutput(hardware: 0, software: 1))
        #expect(BrightnessPolicy.output(level: 0.4, control: .native, settings: settings) == BrightnessOutput(hardware: 0.4, software: 1))
    }
    @Test func malformedInputIsSafe() {
        #expect(BrightnessPolicy.output(level: .nan, control: .software, settings: .init()).software == 1)
        #expect(BrightnessPolicy.output(level: -2, control: .software, settings: .init()).software == 0.1)
        #expect(BrightnessPolicy.output(level: 3, control: .ddc, settings: .init()).hardware == 1)
    }
    @Test func inversionMatchesHardware() {
        #expect(abs(BrightnessPolicy.level(hardware: 0.5, control: .ddc, settings: .init()) - 0.6) < 0.00001)
    }
}
