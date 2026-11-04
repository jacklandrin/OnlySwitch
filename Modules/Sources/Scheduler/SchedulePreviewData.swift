#if DEBUG
import ComposableArchitecture
import Foundation
import RemoteCore

/// Sample schedules and a fake catalog for SwiftUI previews.
enum SchedulePreviewData {
    static let catalog: [RemoteControlDescriptor] = [
        descriptor(.builtIn, "darkMode", "Dark Mode", .switch, "moon.fill"),
        descriptor(.builtIn, "hideDesktop", "Hide Desktop", .switch, "eye.slash"),
        descriptor(.builtIn, "emptyTrash", "Empty Trash", .button, "trash"),
        descriptor(.builtIn, "airPods", "AirPods", .switch, "airpodspro", isAvailable: false, reason: "Not connected"),
        descriptor(.evolution, "8C1F6B1E-6A4D-4E59-9C59-2E3B1C2D4F10", "Mute Mic", .switch, "mic.slash"),
        descriptor(.shortcut, "Morning Routine", "Morning Routine", .button, "sun.max"),
    ]

    static let schedules: [Schedule] = [
        Schedule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Dark Mode at Night",
            target: target(0),
            action: .turnOn,
            trigger: .weekly(days: [], hour: 20, minute: 30),
            activatedAt: Date(timeIntervalSinceNow: -3600),
            lastOutcome: .succeeded,
            lastRunAt: Date(timeIntervalSinceNow: -1800)
        ),
        Schedule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Empty Trash",
            isActive: false,
            target: target(2),
            action: .run,
            trigger: .hourly(minute: 15),
            activatedAt: Date(timeIntervalSinceNow: -7200)
        ),
        Schedule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Morning Routine",
            notifies: true,
            target: target(5),
            action: .run,
            trigger: .weekly(days: ScheduleWeekday.weekdays, hour: 8, minute: 0),
            activatedAt: Date(timeIntervalSinceNow: -600),
            lastOutcome: .failed("The shortcut could not be found."),
            lastRunAt: Date(timeIntervalSinceNow: -300)
        ),
    ]

    @MainActor
    static func store(schedules: [Schedule] = schedules, selecting id: Schedule.ID? = nil) -> StoreOf<SchedulesFeature> {
        var state = SchedulesFeature.State()
        state.schedules = IdentifiedArray(uniqueElements: schedules)
        state.catalog = catalog
        state.hasLoaded = true
        if let id, let schedule = state.schedules[id: id] {
            state.selection = id
            state.editor = ScheduleEditorFeature.State(original: schedule, catalog: catalog)
        }
        return Store(initialState: state) {
            SchedulesFeature()
        } withDependencies: {
            $0.scheduleStorage = ScheduleStorageClient(load: { .loaded([]) }, save: { _ in })
            $0.scheduleExecutor = ScheduleExecutorClient(
                catalog: { catalog },
                run: { _, _ in
                    try? await Task.sleep(for: .seconds(1))
                    return .succeeded
                }
            )
            $0.scheduleNotifications = ScheduleNotificationClient(requestAuthorization: { true }, post: { _, _ in })
        }
    }

    private static func target(_ index: Int) -> ScheduleTarget {
        let descriptor = catalog[index]
        return ScheduleTarget(controlID: descriptor.id, title: descriptor.title, behavior: descriptor.behavior)
    }

    private static func descriptor(
        _ kind: RemoteControlID.Kind,
        _ value: String,
        _ title: String,
        _ behavior: RemoteControlDescriptor.Behavior,
        _ symbol: String,
        isAvailable: Bool = true,
        reason: String? = nil
    ) -> RemoteControlDescriptor {
        RemoteControlDescriptor(
            id: RemoteControlID(kind: kind, value: value),
            title: title,
            behavior: behavior,
            icon: .systemSymbol(symbol),
            isAvailable: isAvailable,
            unavailableReason: reason,
            isDestructive: false,
            supportsStatus: false,
            supportsSecondaryInformation: false
        )
    }
}
#endif
