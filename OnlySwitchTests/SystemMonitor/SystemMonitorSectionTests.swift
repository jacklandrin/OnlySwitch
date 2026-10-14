import Testing
@testable import OnlySwitch

struct SystemMonitorSectionTests {
    @Test
    func sectionOrderKeepsControlsFirstAndUsageLast() {
        #expect(
            SectionBar.sections(authenticator: true, soundMixer: true, systemMonitor: true, codexUsage: true)
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
        (false, false, false, false, [SectionBar.Section.controls]),
        (false, false, false, true, [.controls, .codexUsage]),
        (false, false, true, false, [.controls, .systemMonitor]),
        (false, false, true, true, [.controls, .systemMonitor, .codexUsage]),
        (true, false, false, false, [.controls, .authenticator]),
        (true, false, false, true, [.controls, .authenticator, .codexUsage]),
        (true, false, true, false, [.controls, .authenticator, .systemMonitor]),
        (true, false, true, true, [.controls, .authenticator, .systemMonitor, .codexUsage]),
        (false, true, false, false, [.controls, .soundMixer]),
        (false, true, false, true, [.controls, .soundMixer, .codexUsage]),
        (false, true, true, false, [.controls, .soundMixer, .systemMonitor]),
        (false, true, true, true, [.controls, .soundMixer, .systemMonitor, .codexUsage]),
        (true, true, false, false, [.controls, .authenticator, .soundMixer]),
        (true, true, false, true, [.controls, .authenticator, .soundMixer, .codexUsage]),
        (true, true, true, false, [.controls, .authenticator, .soundMixer, .systemMonitor]),
        (true, true, true, true, [.controls, .authenticator, .soundMixer, .systemMonitor, .codexUsage])
    ])
    func sectionOrderIncludesOnlyEnabledOptionalSections(
        authenticator: Bool,
        soundMixer: Bool,
        systemMonitor: Bool,
        codexUsage: Bool,
        expected: [SectionBar.Section]
    ) {
        #expect(SectionBar.sections(
            authenticator: authenticator,
            soundMixer: soundMixer,
            systemMonitor: systemMonitor,
            codexUsage: codexUsage
        ) == expected)
    }

    @Test
    func aphroditeSectionFollowsItsSharedVisibilityPreference() {
        let shown = SectionBar.sections(
            authenticator: false,
            soundMixer: false,
            systemMonitor: false,
            codexUsage: false,
            aphrodite: true
        )
        let hidden = SectionBar.sections(
            authenticator: false,
            soundMixer: false,
            systemMonitor: false,
            codexUsage: false,
            aphrodite: false
        )

        #expect(shown == [.controls, .aphrodite])
        #expect(hidden == [.controls])
    }
}
