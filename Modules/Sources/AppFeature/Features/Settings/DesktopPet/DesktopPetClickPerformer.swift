import Extensions
import OSLog
import RemoteCore
import Scheduler

/// Runs the configured desktop pet click action. A failed control run (for example a deleted Shortcut)
/// falls back to OnlyControl so a click always responds.
@MainActor
struct DesktopPetClickPerformer {
    var load: () -> DesktopPetClickAction
    var run: (RemoteControlID, ScheduleAction) async -> ScheduleRunOutcome
    var showOnlyControl: () -> Void

    func perform() async {
        switch load() {
        case .onlyControl:
            showOnlyControl()
        case let .control(target):
            let outcome = await run(target.controlID, DesktopPetClickAction.runAction(for: target.behavior))
            if case let .failed(message) = outcome {
                Logger.app.error("Desktop pet click action failed: \(message)")
                showOnlyControl()
            }
        }
    }
}

extension DesktopPetClickPerformer {
    /// Runs controls through the same validated path as schedules and OnlyRemote.
    static func app(showOnlyControl: @escaping @MainActor () -> Void) -> Self {
        let storage = DesktopPetClickActionStorage.liveValue
        let executor = ScheduleExecutorClient.app
        return Self(
            load: { storage.load() },
            run: { id, action in await executor.run(id, action) },
            showOnlyControl: showOnlyControl
        )
    }
}
