import Extensions
import Foundation

extension ScheduleTriggerKind {
    var title: String {
        switch self {
        case .interval: ScheduleStrings.text("Schedule Repeat Interval")
        case .hourly: ScheduleStrings.text("Schedule Every Hour")
        case .weekly: ScheduleStrings.text("Schedule Day Of Week")
        }
    }
}

extension ScheduleIntervalUnit {
    var title: String {
        switch self {
        case .seconds: ScheduleStrings.text("Schedule Seconds")
        case .minutes: ScheduleStrings.text("Schedule Minutes")
        case .hours: ScheduleStrings.text("Schedule Hours")
        }
    }
}
