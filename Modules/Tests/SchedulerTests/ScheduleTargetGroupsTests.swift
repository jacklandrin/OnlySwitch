#if os(macOS)
import Foundation
import RemoteCore
@testable import Scheduler
import Testing

struct ScheduleTargetGroupsTests {
    private let evolutionID = UUID(uuidString: "8C1F6B1E-6A4D-4E59-9C59-2E3B1C2D4F10")!

    private var catalog: [RemoteControlDescriptor] {
        [
            ScheduleFixtures.descriptor(.shortcut("Zen"), title: "Zen", behavior: .button),
            ScheduleFixtures.descriptor(.builtIn("emptyTrash"), title: "Empty Trash", behavior: .button),
            ScheduleFixtures.descriptor(.builtIn("radio"), title: "Radio", behavior: .player),
            ScheduleFixtures.descriptor(.evolution(evolutionID), title: "Mute Mic", behavior: .switch),
            ScheduleFixtures.descriptor(.builtIn("darkMode"), title: "Dark Mode", behavior: .switch),
            ScheduleFixtures.descriptor(.shortcut("Ändern"), title: "Ändern", behavior: .button),
            ScheduleFixtures.descriptor(.builtIn("airDrop"), title: "AirDrop", behavior: .switch),
        ]
    }

    @Test
    func groupsByKindAndBehaviorInFixedOrder() {
        let groups = ScheduleTargetGroups.make(catalog: catalog, search: "")

        #expect(groups.map(\.kind) == [.switches, .buttons, .evolution, .shortcuts])
        #expect(groups[0].descriptors.map(\.title) == ["AirDrop", "Dark Mode", "Radio"])
        #expect(groups[1].descriptors.map(\.title) == ["Empty Trash"])
        #expect(groups[2].descriptors.map(\.title) == ["Mute Mic"])
        #expect(groups[3].descriptors.map(\.title) == ["Ändern", "Zen"])
    }

    @Test
    func searchFiltersTitlesIgnoringCaseAndDiacriticsAndDropsEmptyGroups() {
        let groups = ScheduleTargetGroups.make(catalog: catalog, search: "  an ")

        #expect(groups.map(\.kind) == [.shortcuts])
        #expect(groups[0].descriptors.map(\.title) == ["Ändern"])
    }

    @Test
    func searchWithoutMatchesReturnsNoGroups() {
        #expect(ScheduleTargetGroups.make(catalog: catalog, search: "xyz").isEmpty)
    }

    @Test
    func equalTitlesAreOrderedByIdentifier() {
        let catalog = [
            ScheduleFixtures.descriptor(.builtIn("b"), title: "Same", behavior: .switch),
            ScheduleFixtures.descriptor(.builtIn("a"), title: "Same", behavior: .switch),
        ]

        let groups = ScheduleTargetGroups.make(catalog: catalog, search: "")

        #expect(groups[0].descriptors.map(\.id.value) == ["a", "b"])
    }
}
#endif
