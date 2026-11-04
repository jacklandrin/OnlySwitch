#if os(macOS)
import ComposableArchitecture
import Foundation
import RemoteCore
@testable import Scheduler

extension RemoteControlID {
    static func builtIn(_ value: String) -> Self { Self(kind: .builtIn, value: value) }
    static func shortcut(_ name: String) -> Self { Self(kind: .shortcut, value: name) }
    static func evolution(_ id: UUID) -> Self { Self(kind: .evolution, value: id.uuidString) }
}

enum ScheduleFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    static func schedule(
        _ number: Int,
        name: String? = nil,
        isActive: Bool = true,
        notifies: Bool = false,
        controlID: RemoteControlID = .builtIn("darkMode"),
        action: ScheduleAction = .turnOn,
        trigger: ScheduleTrigger,
        activatedAt: Date,
        lastFiredAt: Date? = nil
    ) -> Schedule {
        Schedule(
            id: id(number),
            name: name ?? "Schedule \(number)",
            isActive: isActive,
            notifies: notifies,
            target: ScheduleTarget(controlID: controlID, title: "Target \(number)", behavior: .switch),
            action: action,
            trigger: trigger,
            activatedAt: activatedAt,
            lastFiredAt: lastFiredAt
        )
    }
}

enum ScheduleTestError: Error, LocalizedError {
    case saveFailed

    var errorDescription: String? { "Disk full" }
}

struct RecordedRun: Equatable, Sendable {
    var controlID: RemoteControlID
    var action: ScheduleAction
}

struct PostedNotification: Equatable, Sendable {
    var title: String
    var body: String
}

/// In-memory dependencies for `SchedulesFeature` that record what the engine did.
final class ScheduleEngineHarness: Sendable {
    let now: LockIsolated<Date>
    let clock = TestClock<Duration>()
    let stored: LockIsolated<ScheduleLoadResult>
    let saves = LockIsolated<[[Schedule]]>([])
    let runs = LockIsolated<[RecordedRun]>([])
    let notifications = LockIsolated<[PostedNotification]>([])
    let outcome: ScheduleRunOutcome
    let failSaves: Bool
    let catalog: [RemoteControlDescriptor]
    /// When set, each run waits for the next value before finishing.
    let gate: AsyncStream<Void>?
    let events = AsyncStream<Void>.makeStream()

    init(
        now: Date,
        stored: ScheduleLoadResult = .loaded([]),
        outcome: ScheduleRunOutcome = .succeeded,
        failSaves: Bool = false,
        catalog: [RemoteControlDescriptor] = [],
        gate: AsyncStream<Void>? = nil
    ) {
        self.now = LockIsolated(now)
        self.stored = LockIsolated(stored)
        self.outcome = outcome
        self.failSaves = failSaves
        self.catalog = catalog
        self.gate = gate
    }

    func advanceDate(by seconds: TimeInterval) {
        now.withValue { $0 = $0.addingTimeInterval(seconds) }
    }

    func apply(to dependencies: inout DependencyValues) {
        dependencies.date = DateGenerator { self.now.value }
        dependencies.calendar = ScheduleFixtures.calendar
        dependencies.continuousClock = clock
        dependencies.scheduleStorage = ScheduleStorageClient(
            load: { self.stored.value },
            save: { schedules in
                if self.failSaves { throw ScheduleTestError.saveFailed }
                self.saves.withValue { $0.append(schedules) }
            }
        )
        dependencies.scheduleExecutor = ScheduleExecutorClient(
            catalog: { self.catalog },
            run: { controlID, action in
                self.runs.withValue { $0.append(RecordedRun(controlID: controlID, action: action)) }
                if let gate = self.gate {
                    for await _ in gate { break }
                }
                return self.outcome
            }
        )
        dependencies.scheduleNotifications = ScheduleNotificationClient(
            requestAuthorization: { true },
            post: { title, body in self.notifications.withValue { $0.append(PostedNotification(title: title, body: body)) } }
        )
        dependencies.scheduleSystemEvents = ScheduleSystemEventsClient(events: { self.events.stream })
    }

    @MainActor
    func makeStore(_ state: SchedulesFeature.State = SchedulesFeature.State()) -> TestStoreOf<SchedulesFeature> {
        TestStore(initialState: state) { SchedulesFeature() } withDependencies: { self.apply(to: &$0) }
    }
}

extension SchedulesFeature.State {
    static func loaded(_ schedules: [Schedule]) -> Self {
        var state = Self()
        state.schedules = IdentifiedArray(uniqueElements: schedules)
        state.hasLoaded = true
        return state
    }
}
#endif
