#if os(macOS)
import Foundation
@testable import Scheduler
import Testing

struct ScheduleWeekdaySelectionTests {
    @Test
    func emptySetContainsEveryDay() {
        #expect(ScheduleWeekday.allCases.allSatisfy { ScheduleWeekdaySelection.contains($0, in: []) })
        #expect(!ScheduleWeekdaySelection.contains(.monday, in: [.sunday]))
    }

    @Test
    func togglingFromEveryDayRemovesThatDay() {
        let result = ScheduleWeekdaySelection.toggling(.sunday, in: [])

        #expect(result == Set(ScheduleWeekday.allCases).subtracting([.sunday]))
    }

    @Test
    func selectingTheSeventhDayNormalizesToEveryDay() {
        let six = Set(ScheduleWeekday.allCases).subtracting([.friday])

        #expect(ScheduleWeekdaySelection.toggling(.friday, in: six).isEmpty)
    }

    @Test
    func theLastSelectedDayCannotBeRemoved() {
        #expect(ScheduleWeekdaySelection.toggling(.monday, in: [.monday]) == [.monday])
        #expect(ScheduleWeekdaySelection.toggling(.monday, in: [.monday, .tuesday]) == [.tuesday])
    }

    @Test
    func orderFollowsTheCalendarsFirstWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2

        #expect(ScheduleWeekdaySelection.ordered(calendar: calendar).first == .monday)
        #expect(ScheduleWeekdaySelection.ordered(calendar: calendar).last == .sunday)
    }
}
#endif
