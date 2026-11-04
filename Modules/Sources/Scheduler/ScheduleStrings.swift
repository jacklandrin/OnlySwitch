import Extensions
import Foundation

/// Every user-facing schedule string key, so the localization test can check the catalog.
public enum ScheduleStrings {
    public static let keys = [
        "Schedules", "Schedule Name", "Schedule Enabled", "Schedule Notification", "Schedule Run", "Schedule When",
        "Schedule Target", "Schedule Choose Target", "Schedule Action", "Schedule Turn On", "Schedule Turn Off",
        "Schedule Run Action", "Schedule Repeat Interval", "Schedule Every Hour", "Schedule Day Of Week",
        "Schedule Seconds", "Schedule Minutes", "Schedule Hours", "Schedule Minute",
        "Schedule Every Day", "Schedule Weekdays", "Schedule Weekends",
        "Schedule Every %lld Seconds", "Schedule Every %lld Minutes", "Schedule Every %lld Hours",
        "Schedule Every Hour At :%@", "Schedule %@ At %@", "Schedule Next Run %@", "Schedule Last Run %@",
        "Schedule Succeeded", "Schedule Failed %@", "Schedule Run Now", "Schedule Save", "Schedule Discard Changes",
        "Schedule New", "Schedule Delete", "Schedule Delete Title %@", "Schedule Delete Message",
        "Schedule Unsaved Title", "Schedule Unsaved Message", "Schedule Search", "Schedule Empty",
        "Schedule Empty Message", "Schedule Manage", "Schedule Inactive", "Schedule Target Unavailable",
        "Schedule Section Switches", "Schedule Section Buttons", "Schedule Section Evolution", "Schedule Section Shortcuts",
        "Schedule Issue Missing Target", "Schedule Issue Action", "Schedule Issue Interval Short",
        "Schedule Issue Interval Long", "Schedule Issue Minute", "Schedule Issue Hour",
        "Schedule Save Failed", "Schedule Notification Ran %@", "Schedule Notification Failed %@",
    ]

    public static func text(_ key: String) -> String {
        key.localized()
    }
}
