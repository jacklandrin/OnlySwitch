import Foundation

/// Rules for the weekday menu, where an empty set means every day.
enum ScheduleWeekdaySelection {
    /// Weekdays in the order the calendar's week starts.
    static func ordered(calendar: Calendar) -> [ScheduleWeekday] {
        ScheduleWeekday.allCases.sorted {
            ($0.rawValue - calendar.firstWeekday + 7) % 7 < ($1.rawValue - calendar.firstWeekday + 7) % 7
        }
    }

    static func contains(_ day: ScheduleWeekday, in days: Set<ScheduleWeekday>) -> Bool {
        days.isEmpty || days.contains(day)
    }

    /// Toggles one day. Selecting all seven normalizes to the empty set; the last selected day cannot be removed.
    static func toggling(_ day: ScheduleWeekday, in days: Set<ScheduleWeekday>) -> Set<ScheduleWeekday> {
        var result = days.isEmpty ? Set(ScheduleWeekday.allCases) : days
        if result.contains(day) {
            guard result.count > 1 else { return days }
            result.remove(day)
        } else {
            result.insert(day)
        }
        return result.count == ScheduleWeekday.allCases.count ? [] : result
    }
}
