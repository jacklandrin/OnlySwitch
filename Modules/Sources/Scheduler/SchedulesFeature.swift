import ComposableArchitecture
import Extensions
import Foundation
import RemoteCore

/// The schedule list and its timing engine: fires due schedules, persists their state and reschedules itself.
@Reducer
public struct SchedulesFeature {
    @ObservableState
    public struct State: Equatable {
        public var schedules: IdentifiedArrayOf<Schedule> = []
        public var catalog: [RemoteControlDescriptor] = []
        public var running: Set<Schedule.ID> = []
        public var hasLoaded = false
        /// Stored data could not be decoded; nothing is saved until the user creates or edits a schedule.
        public var isStorageCorrupted = false
        public var saveError: String?
        public var selection: Schedule.ID?
        public var searchText = ""

        public init() {}
    }

    public enum Action: Equatable, BindableAction {
        /// Loads schedules and starts the engine and system-event observation (once per session).
        case task
        /// Fires due schedules and reschedules the timer.
        case tick
        /// Wake, clock or time-zone change.
        case systemEvent
        case runFinished(Schedule.ID, ScheduleRunOutcome, at: Date)
        case runNow(Schedule.ID)
        case setActive(Schedule.ID, Bool)
        case catalogLoaded([RemoteControlDescriptor])
        case refreshCatalog
        case saveFailed(String)
        case binding(BindingAction<State>)
    }

    enum CancelID { case timer, events }

    /// The engine wakes at least this often, so wall-clock changes are noticed even without a system event.
    static let maximumTimerDelay: TimeInterval = 60
    static let minimumTimerDelay: TimeInterval = 1

    @Dependency(\.date) private var date
    @Dependency(\.calendar) private var calendar
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.scheduleStorage) private var storage
    @Dependency(\.scheduleExecutor) private var executor
    @Dependency(\.scheduleNotifications) private var notifications
    @Dependency(\.scheduleSystemEvents) private var systemEvents

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .task:
                guard !state.hasLoaded else { return .none }
                state.hasLoaded = true
                switch storage.load() {
                case let .loaded(schedules):
                    state.schedules = IdentifiedArray(schedules, uniquingIDsWith: { first, _ in first })
                case .corrupted:
                    state.schedules = []
                    state.isStorageCorrupted = true
                }
                return .merge(
                    .send(.tick),
                    .send(.refreshCatalog),
                    .run { [systemEvents] send in
                        for await _ in systemEvents.events() {
                            await send(.systemEvent)
                        }
                    }
                    .cancellable(id: CancelID.events, cancelInFlight: true)
                )

            case .tick:
                return tick(&state)

            case .systemEvent:
                return .merge(.send(.tick), .send(.refreshCatalog))

            case let .runFinished(id, outcome, finishedAt):
                state.running.remove(id)
                guard var schedule = state.schedules[id: id] else { return .none }
                schedule.lastOutcome = outcome
                schedule.lastRunAt = finishedAt
                state.schedules[id: id] = schedule
                return .merge(persist(state), notify(schedule, outcome: outcome))

            case let .runNow(id):
                guard let schedule = state.schedules[id: id], !state.running.contains(id) else { return .none }
                state.running.insert(id)
                return run(schedule)

            case let .setActive(id, isActive):
                guard state.schedules[id: id] != nil else { return .none }
                state.schedules[id: id]?.isActive = isActive
                if isActive {
                    state.schedules[id: id]?.activatedAt = date.now
                }
                return .merge(persist(state), .send(.tick))

            case .refreshCatalog:
                return .run { [executor] send in
                    await send(.catalogLoaded(await executor.catalog()))
                }

            case let .catalogLoaded(catalog):
                state.catalog = catalog
                return .none

            case let .saveFailed(message):
                state.saveError = message
                return .none
            }
        }
    }

    // MARK: - Engine

    private func tick(_ state: inout State) -> Effect<Action> {
        let now = date.now
        let due = state.schedules
            .compactMap { schedule -> (date: Date, schedule: Schedule)? in
                guard ScheduleCalendar.isDue(schedule, now: now, calendar: calendar),
                      let pending = ScheduleCalendar.pendingFireDate(of: schedule, calendar: calendar) else { return nil }
                return (pending, schedule)
            }
            .sorted { lhs, rhs in
                lhs.date != rhs.date ? lhs.date < rhs.date : lhs.schedule.id.uuidString < rhs.schedule.id.uuidString
            }
            .map(\.schedule)

        var effects: [Effect<Action>] = []
        for schedule in due {
            // The anchor advances even when the previous run is still going, so a busy fire is skipped, not queued.
            state.schedules[id: schedule.id]?.lastFiredAt = now
            if state.running.insert(schedule.id).inserted {
                effects.append(run(schedule))
            }
        }
        if !due.isEmpty {
            effects.append(persist(state))
        }
        effects.append(scheduleTimer(state, now: now))
        return .merge(effects)
    }

    private func run(_ schedule: Schedule) -> Effect<Action> {
        let id = schedule.id
        let controlID = schedule.target.controlID
        let action = schedule.action
        return .run { [executor, date] send in
            let outcome = await executor.run(controlID, action)
            await send(.runFinished(id, outcome, at: date.now))
        }
    }

    private func scheduleTimer(_ state: State, now: Date) -> Effect<Action> {
        let earliest = state.schedules
            .compactMap { ScheduleCalendar.upcomingFireDate(of: $0, now: now, calendar: calendar) }
            .min()
        let delay = Self.timerDelay(until: earliest, now: now)
        return .run { [clock] send in
            try await clock.sleep(for: .seconds(delay))
            await send(.tick)
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
    }

    static func timerDelay(until earliest: Date?, now: Date) -> TimeInterval {
        guard let earliest else { return maximumTimerDelay }
        return min(max(earliest.timeIntervalSince(now), minimumTimerDelay), maximumTimerDelay)
    }

    private func persist(_ state: State) -> Effect<Action> {
        guard !state.isStorageCorrupted else { return .none }
        let schedules = Array(state.schedules)
        return .run { [storage] send in
            do {
                try storage.save(schedules)
            } catch {
                await send(.saveFailed(error.localizedDescription))
            }
        }
    }

    private func notify(_ schedule: Schedule, outcome: ScheduleRunOutcome) -> Effect<Action> {
        guard schedule.notifies else { return .none }
        let key = switch outcome {
        case .succeeded: "Schedule Notification Ran %@"
        case .failed: "Schedule Notification Failed %@"
        }
        let title = key.localizeWithFormat(arguments: schedule.name)
        let body = ScheduleFormatter.outcomeSummary(outcome)
        return .run { [notifications] _ in
            await notifications.post(title, body)
        }
    }
}
