import Testing
@testable import OnlySwitch

struct OnlySwitchListSectionTests {
    @Test
    func codexUsageFollowsThePopoverPreference() {
        let visible = SectionBar.sections(authenticator: false, soundMixer: false, codexUsage: true)
        let hidden = SectionBar.sections(authenticator: false, soundMixer: false, codexUsage: false)

        #expect(visible.contains(.codexUsage))
        #expect(hidden.contains(.codexUsage) == false)
    }
}
