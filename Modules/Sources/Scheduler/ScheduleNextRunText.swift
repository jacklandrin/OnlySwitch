import Extensions
import SwiftUI

/// "Next run: Wed 9:00 AM" for an active schedule; nothing for an inactive one.
struct ScheduleNextRunText: View {
    let schedule: Schedule
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let date = ScheduleCalendar.upcomingFireDate(of: schedule, now: context.date, calendar: calendar) {
                Text("Schedule Next Run %@".localizeWithFormat(arguments: Self.format(date, locale: locale, calendar: calendar)))
            }
        }
    }

    nonisolated static func format(_ date: Date, locale: Locale, calendar: Calendar) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).hour().minute()
        )
    }
}
