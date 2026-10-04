import Testing
@testable import OnlySwitch

struct SystemMonitorSectionTests {
    @Test
    func sectionOrderKeepsControlsFirstAndUsageLast() {
        #expect(
            SectionBar.sections(authenticator: true, soundMixer: true, codexUsage: true)
                == [.controls, .authenticator, .soundMixer, .systemMonitor, .codexUsage]
        )
    }

    @Test
    func temperaturePresentationKeepsUnavailableValuesExplicit() {
        #expect(SystemMonitorTemperaturePresentation.description(.available(42.4)) == "Temperature 42 °C")
        #expect(SystemMonitorTemperaturePresentation.description(.unavailable) == "Temperature unavailable")
    }

    @Test
    func memoryPressurePresentationIsExplicitWithoutRelyingOnColor() {
        #expect(SystemMonitorMemoryPressurePresentation.description(.available(.normal)) == "Memory pressure: Normal")
        #expect(SystemMonitorMemoryPressurePresentation.description(.available(.warning)) == "Memory pressure: Warning")
        #expect(SystemMonitorMemoryPressurePresentation.description(.available(.critical)) == "Memory pressure: Critical")
        #expect(SystemMonitorMemoryPressurePresentation.description(.unavailable) == "Memory pressure: Unavailable")
    }

    @Test(arguments: [
        (false, false, false, [SectionBar.Section.controls, .systemMonitor]),
        (true, false, false, [.controls, .authenticator, .systemMonitor]),
        (false, true, true, [.controls, .soundMixer, .systemMonitor, .codexUsage])
    ])
    func sectionOrderIncludesOnlyEnabledOptionalSections(
        authenticator: Bool,
        soundMixer: Bool,
        codexUsage: Bool,
        expected: [SectionBar.Section]
    ) {
        #expect(SectionBar.sections(authenticator: authenticator, soundMixer: soundMixer, codexUsage: codexUsage) == expected)
    }
}
