import Foundation

/// Pure next-fire calculation for schedules.
public enum ScheduleCalendar {
    public static let minimumIntervalSeconds = 10
    public static let maximumIntervalSeconds = 604_800

    public static func nextFireDate(for trigger: ScheduleTrigger, after date: Date, calendar: Calendar) -> Date? {
        switch trigger {
        case let .interval(value, unit):
            let seconds = min(max(value * unit.seconds, minimumIntervalSeconds), maximumIntervalSeconds)
            return date.addingTimeInterval(TimeInterval(seconds))
        case let .hourly(minute):
            return calendar.nextDate(
                after: date,
                matching: DateComponents(minute: minute, second: 0),
                matchingPolicy: .nextTime
            )
        case let .weekly(days, hour, minute):
            let days = days.isEmpty ? Set(ScheduleWeekday.allCases) : days
            return days.compactMap {
                calendar.nextDate(
                    after: date,
                    matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: $0.rawValue),
                    matchingPolicy: .nextTime
                )
            }.min()
        }
    }

    public static func anchor(of schedule: Schedule) -> Date {
        max(schedule.activatedAt, schedule.lastFiredAt ?? .distantPast)
    }

    /// The first fire after the anchor; may be in the past when a fire was missed.
    public static func pendingFireDate(of schedule: Schedule, calendar: Calendar) -> Date? {
        guard schedule.isActive else { return nil }
        return nextFireDate(for: schedule.trigger, after: anchor(of: schedule), calendar: calendar)
    }

    public static func isDue(_ schedule: Schedule, now: Date, calendar: Calendar) -> Bool {
        pendingFireDate(of: schedule, calendar: calendar).map { $0 <= now } ?? false
    }

    /// What the UI shows as "Next run": now when due, otherwise the pending date.
    public static func upcomingFireDate(of schedule: Schedule, now: Date, calendar: Calendar) -> Date? {
        pendingFireDate(of: schedule, calendar: calendar).map { max($0, now) }
    }
}
