import Extensions
import Foundation

/// Localized, human-readable summaries of schedules.
public enum ScheduleFormatter {
    /// Resolves a `ScheduleStrings` key to its localized format string.
    typealias Localize = @Sendable (String) -> String

    static let appLocalize: Localize = { $0.localized() }

    public static func triggerSummary(_ trigger: ScheduleTrigger, calendar: Calendar, locale: Locale) -> String {
        triggerSummary(trigger, calendar: calendar, locale: locale, localize: appLocalize)
    }

    public static func actionTitle(_ action: ScheduleAction) -> String {
        actionTitle(action, localize: appLocalize)
    }

    public static func daysSummary(_ days: Set<ScheduleWeekday>, calendar: Calendar) -> String {
        daysSummary(days, calendar: calendar, localize: appLocalize)
    }

    public static func issueMessage(_ issue: ScheduleDraftIssue) -> String {
        issueMessage(issue, localize: appLocalize)
    }

    public static func outcomeSummary(_ outcome: ScheduleRunOutcome) -> String {
        outcomeSummary(outcome, localize: appLocalize)
    }

    static func triggerSummary(_ trigger: ScheduleTrigger, calendar: Calendar, locale: Locale, localize: Localize) -> String {
        switch trigger {
        case let .interval(value, unit):
            let key = switch unit {
            case .seconds: "Schedule Every %lld Seconds"
            case .minutes: "Schedule Every %lld Minutes"
            case .hours: "Schedule Every %lld Hours"
            }
            return String(format: localize(key), locale: locale, value)
        case let .hourly(minute):
            let padded = String(format: "%02d", locale: locale, minute)
            return String(format: localize("Schedule Every Hour At :%@"), locale: locale, padded)
        case let .weekly(days, hour, minute):
            let time = timeText(hour: hour, minute: minute, calendar: calendar, locale: locale)
            let daysText = daysSummary(days, calendar: calendar, localize: localize)
            return String(format: localize("Schedule %@ At %@"), locale: locale, daysText, time)
        }
    }

    static func actionTitle(_ action: ScheduleAction, localize: Localize) -> String {
        switch action {
        case .turnOn: localize("Schedule Turn On")
        case .turnOff: localize("Schedule Turn Off")
        case .run: localize("Schedule Run Action")
        }
    }

    static func daysSummary(_ days: Set<ScheduleWeekday>, calendar: Calendar, localize: Localize) -> String {
        if days.isEmpty || days.count == ScheduleWeekday.allCases.count { return localize("Schedule Every Day") }
        if days == ScheduleWeekday.weekdays { return localize("Schedule Weekdays") }
        if days == ScheduleWeekday.weekends { return localize("Schedule Weekends") }
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday
        return days
            .sorted { ($0.rawValue - first + 7) % 7 < ($1.rawValue - first + 7) % 7 }
            .map { symbols[$0.rawValue - 1] }
            .joined(separator: ", ")
    }

    static func issueMessage(_ issue: ScheduleDraftIssue, localize: Localize) -> String {
        switch issue {
        case .missingTarget: localize("Schedule Issue Missing Target")
        case .actionNotAllowed: localize("Schedule Issue Action")
        case .intervalTooShort: localize("Schedule Issue Interval Short")
        case .intervalTooLong: localize("Schedule Issue Interval Long")
        case .invalidMinute: localize("Schedule Issue Minute")
        case .invalidHour: localize("Schedule Issue Hour")
        }
    }

    static func outcomeSummary(_ outcome: ScheduleRunOutcome, localize: Localize) -> String {
        switch outcome {
        case .succeeded: localize("Schedule Succeeded")
        case let .failed(message): String(format: localize("Schedule Failed %@"), message)
        }
    }

    private static func timeText(hour: Int, minute: Int, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", locale: locale, hour, minute)
        }
        return formatter.string(from: date)
    }
}
