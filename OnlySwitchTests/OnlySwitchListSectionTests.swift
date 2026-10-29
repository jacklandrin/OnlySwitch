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

    @Test
    func singleColumnBarFitsFiveTabsAndScrollsBeyondThat() {
        let limit = SectionBar.singleColumnVisibleSegmentLimit
        #expect(limit == 5)
        #expect(SectionBar.visibleSegmentCount(for: 3, limit: limit) == 3)
        #expect(SectionBar.visibleSegmentCount(for: 5, limit: limit) == 5)
        #expect(SectionBar.visibleSegmentCount(for: 6, limit: limit) == 5)
        #expect(SectionBar.visibleSegmentCount(for: 10, limit: limit) == 5)
    }

    @Test
    func barWithoutLimitFitsEveryTab() {
        #expect(SectionBar.visibleSegmentCount(for: 10, limit: nil) == 10)
        #expect(SectionBar.visibleSegmentCount(for: 0, limit: nil) == 1)
    }

    @Test
    func verticalWheelMovementScrollsTheBarSideways() {
        #expect(SectionBar.horizontalScrollDelta(deltaX: 0, deltaY: -1, hasPreciseDeltas: false) == -SectionBar.wheelLineScrollDistance)
        #expect(SectionBar.horizontalScrollDelta(deltaX: 0.5, deltaY: 6, hasPreciseDeltas: true) == 6)
    }

    @Test
    func horizontalOrIdleWheelEventsKeepNativeHandling() {
        #expect(SectionBar.horizontalScrollDelta(deltaX: 8, deltaY: 2, hasPreciseDeltas: true) == nil)
        #expect(SectionBar.horizontalScrollDelta(deltaX: 3, deltaY: 3, hasPreciseDeltas: true) == nil)
        #expect(SectionBar.horizontalScrollDelta(deltaX: 0, deltaY: 0, hasPreciseDeltas: false) == nil)
    }
}
