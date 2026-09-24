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
