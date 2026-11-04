import Foundation

/// Converts a weekly trigger's hour and minute to and from the `Date` a time-only `DatePicker` edits.
struct ScheduleTimeOfDay: Equatable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Reads the wall-clock hour and minute of `date` in `calendar`'s time zone.
    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// The time on a fixed reference day (1 Jan 2001), so DST changes on the current day never shift it.
    func date(in calendar: Calendar) -> Date {
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }
}
