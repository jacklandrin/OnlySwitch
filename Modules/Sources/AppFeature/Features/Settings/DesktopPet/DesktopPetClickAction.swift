import RemoteCore
import Scheduler

/// What clicking the desktop pet does.
enum DesktopPetClickAction: Codable, Hashable, Sendable {
    case onlyControl
    case control(ScheduleTarget)

    /// The saved control, when the pet runs one.
    var target: ScheduleTarget? {
        if case let .control(target) = self { target } else { nil }
    }

    /// Buttons, Evolutions and Shortcuts run; switches and players toggle.
    static func runAction(for behavior: RemoteControlDescriptor.Behavior) -> ScheduleAction {
        behavior == .button ? .run : .toggle
    }
}
