import Testing
@testable import OnlySwitch

struct OnlySwitchListSectionTests {
    @Test
    func codexUsageFollowsThePopoverPreference() {
        let visible = SectionBar.sections(authenticator: false, soundMixer: false, systemMonitor: false, codexUsage: true)
        let hidden = SectionBar.sections(authenticator: false, soundMixer: false, systemMonitor: false, codexUsage: false)

        #expect(visible.contains(.codexUsage))
        #expect(hidden.contains(.codexUsage) == false)
    }

    @Test
    func singleControlsSectionHidesTheSectionBar() {
        let sections = SectionBar.sections(
            authenticator: false,
            soundMixer: false,
            systemMonitor: false,
            codexUsage: false
        )

        #expect(sections == [.controls])
        #expect(SectionBar.shouldShowBar(for: sections) == false)
        #expect(SectionBar.shouldShowBar(for: [.controls, .systemMonitor]))
    }
}
