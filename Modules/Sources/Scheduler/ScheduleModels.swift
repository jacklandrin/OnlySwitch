import Foundation
import RemoteCore

/// What a schedule does to its target when it fires.
public enum ScheduleAction: String, Codable, CaseIterable, Sendable {
    case turnOn, turnOff, toggle, run

    /// Whether running needs the target's current state first.
    public var needsCurrentState: Bool { self == .toggle }

    /// `nil` when toggling a target whose current state is unknown.
    public func remoteAction(currentlyOn: Bool? = nil) -> RemoteControlAction? {
        switch self {
        case .turnOn: .setState(true)
        case .turnOff: .setState(false)
        case .toggle: currentlyOn.map { .setState(!$0) }
        case .run: .trigger
        }
    }

    public static func allowed(for behavior: RemoteControlDescriptor.Behavior) -> [ScheduleAction] {
        behavior == .button ? [.run] : [.turnOn, .turnOff, .toggle]
    }
}

/// The control a schedule runs, identified the same way as the remote catalog.
public struct ScheduleTarget: Codable, Hashable, Sendable {
    public var controlID: RemoteControlID
    /// Title captured when saved, shown when the control is no longer in the catalog.
    public var title: String
    public var behavior: RemoteControlDescriptor.Behavior

    public init(controlID: RemoteControlID, title: String, behavior: RemoteControlDescriptor.Behavior) {
        self.controlID = controlID
        self.title = title
        self.behavior = behavior
    }
}

public enum ScheduleIntervalUnit: String, Codable, CaseIterable, Sendable {
    case seconds, minutes, hours

    public var seconds: Int {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3600
        }
    }
}

/// Raw values match `Calendar` weekday numbering (1 = Sunday).
public enum ScheduleWeekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let weekdays: Set<Self> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let weekends: Set<Self> = [.saturday, .sunday]
}

public enum ScheduleTrigger: Codable, Hashable, Sendable {
    case interval(value: Int, unit: ScheduleIntervalUnit)
    case hourly(minute: Int)
    /// Empty `days` means every day.
    case weekly(days: Set<ScheduleWeekday>, hour: Int, minute: Int)
}

public enum ScheduleRunOutcome: Codable, Hashable, Sendable {
    case succeeded
    case failed(String)
}

public struct Schedule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isActive: Bool
    public var notifies: Bool
    public var target: ScheduleTarget
    public var action: ScheduleAction
    public var trigger: ScheduleTrigger
    /// Reset on activation and on trigger changes so saving never fires immediately.
    public var activatedAt: Date
    public var lastFiredAt: Date?
    public var lastOutcome: ScheduleRunOutcome?
    public var lastRunAt: Date?

    public init(
        id: UUID,
        name: String,
        isActive: Bool = true,
        notifies: Bool = false,
        target: ScheduleTarget,
        action: ScheduleAction,
        trigger: ScheduleTrigger,
        activatedAt: Date,
        lastFiredAt: Date? = nil,
        lastOutcome: ScheduleRunOutcome? = nil,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.notifies = notifies
        self.target = target
        self.action = action
        self.trigger = trigger
        self.activatedAt = activatedAt
        self.lastFiredAt = lastFiredAt
        self.lastOutcome = lastOutcome
        self.lastRunAt = lastRunAt
    }
}
