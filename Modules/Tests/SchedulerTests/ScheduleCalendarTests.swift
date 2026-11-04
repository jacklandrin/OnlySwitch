#if os(macOS)
import Foundation
import RemoteCore
import Testing
@testable import Scheduler

struct ScheduleCalendarTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    func schedule(
        trigger: ScheduleTrigger,
        isActive: Bool = true,
        activatedAt: Date,
        lastFiredAt: Date? = nil
    ) -> Schedule {
        Schedule(
            id: UUID(),
            name: "Test",
            isActive: isActive,
            target: ScheduleTarget(
                controlID: RemoteControlID(kind: .builtIn, value: "darkMode"),
                title: "Dark Mode",
                behavior: .switch
            ),
            action: .turnOn,
            trigger: trigger,
            activatedAt: activatedAt,
            lastFiredAt: lastFiredAt
        )
    }

    // MARK: - Interval

    @Test func intervalAddsSeconds() {
        let t = date(2026, 11, 4, 10, 0)
        let next = ScheduleCalendar.nextFireDate(for: .interval(value: 10, unit: .seconds), after: t, calendar: calendar)
        #expect(next == t.addingTimeInterval(10))
    }

    @Test func intervalClampsToMinimum() {
        let t = date(2026, 11, 4, 10, 0)
        let next = ScheduleCalendar.nextFireDate(for: .interval(value: 1, unit: .seconds), after: t, calendar: calendar)
        #expect(next == t.addingTimeInterval(10))
    }

    @Test func intervalClampsToMaximum() {
        let t = date(2026, 11, 4, 10, 0)
        let next = ScheduleCalendar.nextFireDate(for: .interval(value: 240, unit: .hours), after: t, calendar: calendar)
        #expect(next == t.addingTimeInterval(604_800))
    }

    @Test func intervalLimits() {
        #expect(ScheduleCalendar.minimumIntervalSeconds == 10)
        #expect(ScheduleCalendar.maximumIntervalSeconds == 604_800)
    }

    // MARK: - Hourly

    @Test func hourlyFiresLaterInSameHour() {
        let next = ScheduleCalendar.nextFireDate(for: .hourly(minute: 5), after: date(2026, 11, 4, 10, 4, 59), calendar: calendar)
        #expect(next == date(2026, 11, 4, 10, 5))
    }

    @Test func hourlyAtExactMinuteMovesToNextHour() {
        let next = ScheduleCalendar.nextFireDate(for: .hourly(minute: 5), after: date(2026, 11, 4, 10, 5), calendar: calendar)
        #expect(next == date(2026, 11, 4, 11, 5))
    }

    // MARK: - Weekly

    @Test func weeklySingleDay() {
        // Sunday 2026-11-01 12:00 → Monday 2026-11-02 09:00.
        let next = ScheduleCalendar.nextFireDate(
            for: .weekly(days: [.monday], hour: 9, minute: 0),
            after: date(2026, 11, 1, 12, 0),
            calendar: calendar
        )
        #expect(next == date(2026, 11, 2, 9, 0))
    }

    @Test func weeklyPicksEarliestOfSeveralDays() {
        // Tuesday 2026-11-03 12:00 → Friday 2026-11-06 09:00.
        let next = ScheduleCalendar.nextFireDate(
            for: .weekly(days: [.monday, .friday], hour: 9, minute: 0),
            after: date(2026, 11, 3, 12, 0),
            calendar: calendar
        )
        #expect(next == date(2026, 11, 6, 9, 0))
    }

    @Test func weeklyEmptyDaysMeansEveryDay() {
        let next = ScheduleCalendar.nextFireDate(
            for: .weekly(days: [], hour: 9, minute: 0),
            after: date(2026, 11, 4, 23, 30),
            calendar: calendar
        )
        #expect(next == date(2026, 11, 5, 9, 0))
    }

    // MARK: - DST

    @Test func springForwardSkippedTimeFiresAtNextValidInstant() {
        // 2027-03-14 02:30 does not exist in New York; clocks jump 02:00 → 03:00 EDT.
        let next = ScheduleCalendar.nextFireDate(
            for: .weekly(days: [], hour: 2, minute: 30),
            after: date(2027, 3, 13, 12, 0),
            calendar: calendar
        )
        let expected = calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "America/New_York")!,
            year: 2027, month: 3, day: 14, hour: 3, minute: 0
        ))
        #expect(next == expected)
        #expect(next.map { calendar.component(.hour, from: $0) } == 3)
    }

    @Test func fallBackRepeatedHourFiresOnce() throws {
        // 2026-11-01 01:30 occurs twice in New York (EDT then EST).
        let trigger = ScheduleTrigger.weekly(days: [], hour: 1, minute: 30)
        let first = try #require(ScheduleCalendar.nextFireDate(for: trigger, after: date(2026, 10, 31, 12, 0), calendar: calendar))
        let firstParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: first)
        #expect(firstParts == DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))
        // The first (EDT, UTC-4) occurrence: 2026-11-01 05:30 UTC.
        #expect(first == Date(timeIntervalSince1970: 1_793_511_000))

        let second = try #require(ScheduleCalendar.nextFireDate(for: trigger, after: first, calendar: calendar))
        let secondParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: second)
        #expect(secondParts == DateComponents(year: 2026, month: 11, day: 2, hour: 1, minute: 30))
    }

    // MARK: - Anchor / due / upcoming

    @Test func anchorUsesLaterOfActivatedAndLastFired() {
        let early = date(2026, 11, 4, 8, 0)
        let late = date(2026, 11, 4, 9, 0)
        #expect(ScheduleCalendar.anchor(of: schedule(trigger: .hourly(minute: 0), activatedAt: early, lastFiredAt: late)) == late)
        #expect(ScheduleCalendar.anchor(of: schedule(trigger: .hourly(minute: 0), activatedAt: late, lastFiredAt: early)) == late)
        #expect(ScheduleCalendar.anchor(of: schedule(trigger: .hourly(minute: 0), activatedAt: early)) == early)
    }

    @Test func inactiveScheduleIsNeverDue() {
        let item = schedule(trigger: .hourly(minute: 0), isActive: false, activatedAt: date(2026, 11, 4, 8, 30))
        #expect(!ScheduleCalendar.isDue(item, now: date(2026, 11, 4, 12, 10), calendar: calendar))
        #expect(ScheduleCalendar.pendingFireDate(of: item, calendar: calendar) == nil)
        #expect(ScheduleCalendar.upcomingFireDate(of: item, now: date(2026, 11, 4, 12, 10), calendar: calendar) == nil)
    }

    @Test func missedFiresCatchUpOnceThenResumeCadence() {
        let now = date(2026, 11, 4, 12, 10)
        var item = schedule(trigger: .hourly(minute: 0), activatedAt: date(2026, 11, 4, 8, 30))
        #expect(ScheduleCalendar.isDue(item, now: now, calendar: calendar))
        #expect(ScheduleCalendar.pendingFireDate(of: item, calendar: calendar) == date(2026, 11, 4, 9, 0))
        #expect(ScheduleCalendar.upcomingFireDate(of: item, now: now, calendar: calendar) == now)

        item.lastFiredAt = now
        #expect(!ScheduleCalendar.isDue(item, now: now, calendar: calendar))
        #expect(!ScheduleCalendar.isDue(item, now: date(2026, 11, 4, 12, 59, 59), calendar: calendar))
        #expect(ScheduleCalendar.isDue(item, now: date(2026, 11, 4, 13, 0), calendar: calendar))
        #expect(ScheduleCalendar.upcomingFireDate(of: item, now: now, calendar: calendar) == date(2026, 11, 4, 13, 0))
    }
}
#endif
