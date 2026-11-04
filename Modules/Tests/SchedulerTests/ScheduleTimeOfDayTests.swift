#if os(macOS)
import Foundation
@testable import Scheduler
import Testing

struct ScheduleTimeOfDayTests {
    @Test(arguments: [(0, 0), (9, 5), (13, 30), (23, 59)])
    func roundTripsThroughDate(hour: Int, minute: Int) {
        let calendar = ScheduleFixtures.calendar
        let date = ScheduleTimeOfDay(hour: hour, minute: minute).date(in: calendar)

        #expect(ScheduleTimeOfDay(date: date, calendar: calendar) == ScheduleTimeOfDay(hour: hour, minute: minute))
    }

    @Test
    func readsWallClockTimeInTheCalendarsTimeZone() {
        let date = ScheduleFixtures.date(2026, 3, 8, 3, 15)

        #expect(ScheduleTimeOfDay(date: date, calendar: ScheduleFixtures.calendar) == ScheduleTimeOfDay(hour: 3, minute: 15))
    }
}
#endif
