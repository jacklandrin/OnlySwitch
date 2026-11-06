#if os(macOS)
import Foundation
import Testing
@testable import Scheduler

/// The package test bundle has no app `en.lproj`, so `.localized()` returns keys here.
/// These tests inject a lookup backed by the catalog's English values instead.
struct ScheduleFormatterTests {
    private static let english: [String: String] = {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let data = try? Data(contentsOf: repository.appendingPathComponent("Localization/Localizable.xcstrings")),
              let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = catalog["strings"] as? [String: [String: Any]]
        else { return [:] }
        var result: [String: String] = [:]
        for key in ScheduleStrings.keys {
            let localizations = strings[key]?["localizations"] as? [String: [String: Any]]
            let unit = localizations?["en"]?["stringUnit"] as? [String: String]
            if let value = unit?["value"] { result[key] = value }
        }
        return result
    }()

    private let localize: ScheduleFormatter.Localize = { english[$0] ?? $0 }
    private let locale = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func everyKeyHasAnEnglishValue() {
        #expect(Set(ScheduleStrings.keys).count == ScheduleStrings.keys.count)
        for key in ScheduleStrings.keys {
            #expect(Self.english[key] != nil, "Missing en value: \(key)")
            #expect(key == "Schedules" || key.hasPrefix("Schedule "))
        }
    }

    @Test func weekdaysSetIsSummarized() {
        #expect(ScheduleFormatter.daysSummary(ScheduleWeekday.weekdays, calendar: calendar, localize: localize) == "Weekdays")
    }

    @Test func weekendsSetIsSummarized() {
        #expect(ScheduleFormatter.daysSummary(ScheduleWeekday.weekends, calendar: calendar, localize: localize) == "Weekends")
    }

    @Test func emptyAndFullSetsMeanEveryDay() {
        #expect(ScheduleFormatter.daysSummary([], calendar: calendar, localize: localize) == "Every Day")
        #expect(ScheduleFormatter.daysSummary(Set(ScheduleWeekday.allCases), calendar: calendar, localize: localize) == "Every Day")
    }

    @Test func otherDaysUseShortSymbolsInWeekOrder() {
        #expect(ScheduleFormatter.daysSummary([.wednesday, .monday], calendar: calendar, localize: localize) == "Mon, Wed")
        #expect(ScheduleFormatter.daysSummary([.saturday, .sunday, .monday], calendar: calendar, localize: localize) == "Sun, Mon, Sat")
    }

    @Test func dayOrderFollowsFirstWeekday() {
        var calendar = calendar
        calendar.firstWeekday = 2
        #expect(ScheduleFormatter.daysSummary([.saturday, .sunday, .monday], calendar: calendar, localize: localize) == "Mon, Sat, Sun")
    }

    @Test func intervalSummaries() {
        #expect(ScheduleFormatter.triggerSummary(.interval(value: 10, unit: .minutes), calendar: calendar, locale: locale, localize: localize) == "Every 10 minutes")
        #expect(ScheduleFormatter.triggerSummary(.interval(value: 30, unit: .seconds), calendar: calendar, locale: locale, localize: localize) == "Every 30 seconds")
        #expect(ScheduleFormatter.triggerSummary(.interval(value: 2, unit: .hours), calendar: calendar, locale: locale, localize: localize) == "Every 2 hours")
    }

    @Test func hourlySummaryPadsMinute() {
        #expect(ScheduleFormatter.triggerSummary(.hourly(minute: 5), calendar: calendar, locale: locale, localize: localize) == "Every hour at :05")
    }

    @Test func weeklySummaryCombinesDaysAndTime() {
        let summary = ScheduleFormatter.triggerSummary(
            .weekly(days: ScheduleWeekday.weekdays, hour: 21, minute: 5),
            calendar: calendar, locale: locale, localize: localize
        )
        #expect(summary.hasPrefix("Weekdays at 9:05"))
        #expect(summary.hasSuffix("PM"))
    }

    @Test func actionTitles() {
        #expect(ScheduleFormatter.actionTitle(.turnOn, localize: localize) == "Turn On")
        #expect(ScheduleFormatter.actionTitle(.turnOff, localize: localize) == "Turn Off")
        #expect(ScheduleFormatter.actionTitle(.toggle, localize: localize) == "Toggle")
        #expect(ScheduleFormatter.actionTitle(.run, localize: localize) == "Run")
    }

    @Test(arguments: [
        ScheduleDraftIssue.missingTarget, .actionNotAllowed, .intervalTooShort, .intervalTooLong, .invalidMinute, .invalidHour,
    ])
    func everyIssueHasAMessage(issue: ScheduleDraftIssue) {
        let message = ScheduleFormatter.issueMessage(issue, localize: localize)
        #expect(message.isEmpty == false)
        #expect(message.hasPrefix("Schedule ") == false)
    }

    @Test func outcomeSummaries() {
        #expect(ScheduleFormatter.outcomeSummary(.succeeded, localize: localize) == "Succeeded")
        let failed = ScheduleFormatter.outcomeSummary(.failed("Not found"), localize: localize)
        #expect(failed.contains("Not found"))
        #expect(failed.hasPrefix("Schedule ") == false)
    }

    @Test func nextRunDateFollowsTheGivenLocale() {
        let date = ScheduleFixtures.date(2026, 11, 4, 9, 0)
        let german = ScheduleNextRunText.format(date, locale: Locale(identifier: "de"), calendar: ScheduleFixtures.calendar)
        let english = ScheduleNextRunText.format(date, locale: locale, calendar: ScheduleFixtures.calendar)
        #expect(german.hasPrefix("Mi"))
        #expect(english.hasPrefix("Wed"))
        #expect(english.contains("9:00"))
    }
}
#endif
