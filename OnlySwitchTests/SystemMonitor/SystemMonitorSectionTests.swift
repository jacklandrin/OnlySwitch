import Testing
@testable import OnlySwitch

struct SystemMonitorSectionTests {
    @Test
    func sectionOrderKeepsControlsFirstAndMonitorLast() {
        #expect(
            SectionBar.sections(authenticator: true, soundMixer: true)
                == [.controls, .authenticator, .soundMixer, .systemMonitor]
        )
    }

    @Test
    func temperaturePresentationKeepsUnavailableValuesExplicit() {
        #expect(SystemMonitorTemperaturePresentation.description(.available(42.4)) == "Temperature 42 °C")
        #expect(SystemMonitorTemperaturePresentation.description(.unavailable) == "Temperature unavailable")
    }

    @Test(arguments: [
        (false, false, [SectionBar.Section.controls, .systemMonitor]),
        (true, false, [.controls, .authenticator, .systemMonitor]),
        (false, true, [.controls, .soundMixer, .systemMonitor])
    ])
    func sectionOrderIncludesOnlyEnabledOptionalSections(
        authenticator: Bool,
        soundMixer: Bool,
        expected: [SectionBar.Section]
    ) {
        #expect(SectionBar.sections(authenticator: authenticator, soundMixer: soundMixer) == expected)
    }
}
