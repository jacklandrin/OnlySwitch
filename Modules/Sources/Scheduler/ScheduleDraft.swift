import Foundation

public enum ScheduleTriggerKind: String, CaseIterable, Sendable {
    case interval, hourly, weekly
}

public enum ScheduleDraftIssue: Equatable, Sendable {
    case missingTarget, actionNotAllowed, intervalTooShort, intervalTooLong, invalidMinute, invalidHour
}

public struct ScheduleDraftIssues: Error, Equatable {
    public var issues: [ScheduleDraftIssue]

    public init(issues: [ScheduleDraftIssue]) {
        self.issues = issues
    }
}

/// Editable form state for a schedule; validated before it becomes a `Schedule`.
public struct ScheduleDraft: Equatable, Sendable {
    public var name = ""
    public var isActive = true
    public var notifies = false
    public var target: ScheduleTarget?
    public var action: ScheduleAction = .turnOn
    public var triggerKind: ScheduleTriggerKind = .weekly
    public var intervalValue = 10
    public var intervalUnit: ScheduleIntervalUnit = .minutes
    public var hourlyMinute = 0
    public var weeklyDays: Set<ScheduleWeekday> = []
    public var weeklyHour = 9
    public var weeklyMinute = 0

    public init() {}

    public init(_ schedule: Schedule) {
        name = schedule.name
        isActive = schedule.isActive
        notifies = schedule.notifies
        target = schedule.target
        action = schedule.action
        switch schedule.trigger {
        case let .interval(value, unit):
            triggerKind = .interval
            intervalValue = value
            intervalUnit = unit
        case let .hourly(minute):
            triggerKind = .hourly
            hourlyMinute = minute
        case let .weekly(days, hour, minute):
            triggerKind = .weekly
            weeklyDays = days
            weeklyHour = hour
            weeklyMinute = minute
        }
    }

    public var trigger: ScheduleTrigger {
        switch triggerKind {
        case .interval: .interval(value: intervalValue, unit: intervalUnit)
        case .hourly: .hourly(minute: hourlyMinute)
        case .weekly: .weekly(days: weeklyDays, hour: weeklyHour, minute: weeklyMinute)
        }
    }

    /// Picks the first allowed action when the target's behavior changes.
    public mutating func setTarget(_ target: ScheduleTarget) {
        self.target = target
        let allowed = ScheduleAction.allowed(for: target.behavior)
        if !allowed.contains(action), let first = allowed.first {
            action = first
        }
    }

    public func issues() -> [ScheduleDraftIssue] {
        var issues: [ScheduleDraftIssue] = []
        if let target {
            if !ScheduleAction.allowed(for: target.behavior).contains(action) {
                issues.append(.actionNotAllowed)
            }
        } else {
            issues.append(.missingTarget)
        }
        switch triggerKind {
        case .interval:
            let (seconds, overflow) = intervalValue.multipliedReportingOverflow(by: intervalUnit.seconds)
            if !overflow, seconds < ScheduleCalendar.minimumIntervalSeconds {
                issues.append(.intervalTooShort)
            } else if overflow || seconds > ScheduleCalendar.maximumIntervalSeconds {
                issues.append(.intervalTooLong)
            }
        case .hourly:
            if !(0...59).contains(hourlyMinute) { issues.append(.invalidMinute) }
        case .weekly:
            if !(0...23).contains(weeklyHour) { issues.append(.invalidHour) }
            if !(0...59).contains(weeklyMinute) { issues.append(.invalidMinute) }
        }
        return issues
    }

    /// `id`/`activatedAt` from `original` are kept unless the trigger changed or it is being (re)activated.
    public func makeSchedule(original: Schedule?, id: UUID, now: Date) throws(ScheduleDraftIssues) -> Schedule {
        let issues = issues()
        guard issues.isEmpty, let target else {
            throw ScheduleDraftIssues(issues: issues)
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trigger = trigger
        let keepsAnchor = original.map { $0.trigger == trigger && ($0.isActive || !isActive) } ?? false
        return Schedule(
            id: original?.id ?? id,
            name: trimmedName.isEmpty ? target.title.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedName,
            isActive: isActive,
            notifies: notifies,
            target: target,
            action: action,
            trigger: trigger,
            activatedAt: keepsAnchor ? original?.activatedAt ?? now : now,
            lastFiredAt: original?.lastFiredAt,
            lastOutcome: original?.lastOutcome,
            lastRunAt: original?.lastRunAt
        )
    }
}
