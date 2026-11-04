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
        @Presents public var editor: ScheduleEditorFeature.State?
        @Presents public var alert: AlertState<Action.Alert>?

        public init() {}

        /// Schedules whose name or target title contains `searchText`, ignoring case and diacritics.
        public var filteredSchedules: IdentifiedArrayOf<Schedule> {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return schedules }
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            return schedules.filter {
                $0.name.range(of: query, options: options) != nil
                    || $0.target.title.range(of: query, options: options) != nil
            }
        }
    }

    public enum Action: Equatable, BindableAction {
        /// Loads schedules and starts the engine and system-event observation (once per session).
        case task
        /// Fires due schedules and reschedules the timer.
        case tick
        /// Wake, clock or time-zone change.
        case systemEvent
        case runFinished(Schedule.ID, ScheduleRunOutcome, at: Date)
        /// Runs the schedule now, even when it is inactive; does not move its fire anchor.
        case runNow(Schedule.ID)
        case setActive(Schedule.ID, Bool)
        case catalogLoaded([RemoteControlDescriptor])
        case refreshCatalog
        case binding(BindingAction<State>)
        /// Opens an empty draft, asking first when the open editor has unsaved changes.
        case addTapped
        /// Opens the editor for a schedule (`nil` closes it), asking first when there are unsaved changes.
        case select(Schedule.ID?)
        case deleteTapped(Schedule.ID)
        case editor(PresentationAction<ScheduleEditorFeature.Action>)
        case alert(PresentationAction<Alert>)

        public enum Alert: Equatable {
            case confirmDelete(Schedule.ID)
            case discardAndSelect(Schedule.ID?)
            case discardAndAdd
        }
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
            case .binding, .alert(.dismiss):
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
                persist(&state)
                return notify(schedule, outcome: outcome)

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
                persist(&state)
                return .send(.tick)

            case .refreshCatalog:
                return .run { [executor] send in
                    await send(.catalogLoaded(await executor.catalog()))
                }

            case let .catalogLoaded(catalog):
                state.catalog = catalog
                state.editor?.catalog = catalog
                return .none

            case .addTapped:
                if state.editor?.isDirty == true {
                    state.alert = Self.unsavedChangesAlert(.discardAndAdd)
                } else {
                    openNewDraft(&state)
                }
                return .none

            case let .select(id):
                guard id != state.selection else { return .none }
                if state.editor?.isDirty == true {
                    state.alert = Self.unsavedChangesAlert(.discardAndSelect(id))
                } else {
                    openEditor(for: id, in: &state)
                }
                return .none

            case let .deleteTapped(id):
                guard let schedule = state.schedules[id: id] else { return .none }
                state.alert = Self.deleteAlert(for: schedule)
                return .none

            case let .alert(.presented(.confirmDelete(id))):
                guard state.schedules.remove(id: id) != nil else { return .none }
                // A run already in progress finishes on its own; its result is ignored because the schedule is gone.
                if state.selection == id || state.editor?.original?.id == id {
                    state.selection = nil
                    state.editor = nil
                }
                persist(&state)
                return .send(.tick)

            case let .alert(.presented(.discardAndSelect(id))):
                openEditor(for: id, in: &state)
                return .none

            case .alert(.presented(.discardAndAdd)):
                openNewDraft(&state)
                return .none

            case let .editor(.presented(.delegate(.save(schedule)))):
                if state.schedules[id: schedule.id] != nil {
                    state.schedules[id: schedule.id] = schedule
                } else {
                    state.schedules.append(schedule)
                }
                state.selection = schedule.id
                // The user explicitly saved, so the undecodable data may now be replaced.
                state.isStorageCorrupted = false
                persist(&state)
                let hasRequestedAuthorization = state.editor?.hasRequestedNotificationAuthorization ?? false
                let isAuthorized = state.editor?.isNotificationAuthorized
                state.editor = ScheduleEditorFeature.State(original: schedule, catalog: state.catalog)
                state.editor?.hasRequestedNotificationAuthorization = hasRequestedAuthorization
                state.editor?.isNotificationAuthorized = isAuthorized
                return .send(.tick)

            case .editor(.presented(.delegate(.discard))):
                guard let original = state.editor?.original else {
                    state.editor = nil
                    return .none
                }
                state.editor = ScheduleEditorFeature.State(
                    original: state.schedules[id: original.id] ?? original,
                    catalog: state.catalog
                )
                return .none

            case .editor:
                return .none
            }
        }
        .ifLet(\.$editor, action: \.editor) { ScheduleEditorFeature() }
        .ifLet(\.$alert, action: \.alert)
    }

    // MARK: - Editing

    private func openNewDraft(_ state: inout State) {
        state.selection = nil
        state.editor = ScheduleEditorFeature.State(original: nil, catalog: state.catalog)
    }

    private func openEditor(for id: Schedule.ID?, in state: inout State) {
        guard let id, let schedule = state.schedules[id: id] else {
            state.selection = nil
            state.editor = nil
            return
        }
        state.selection = id
        state.editor = ScheduleEditorFeature.State(original: schedule, catalog: state.catalog)
    }

    static func unsavedChangesAlert(_ discardAction: Action.Alert) -> AlertState<Action.Alert> {
        AlertState {
            TextState(ScheduleStrings.text("Schedule Unsaved Title"))
        } actions: {
            ButtonState(role: .destructive, action: discardAction) {
                TextState(ScheduleStrings.text("Schedule Discard Changes"))
            }
            ButtonState(role: .cancel) {
                TextState(ScheduleStrings.text("Cancel"))
            }
        } message: {
            TextState(ScheduleStrings.text("Schedule Unsaved Message"))
        }
    }

    static func deleteAlert(for schedule: Schedule) -> AlertState<Action.Alert> {
        AlertState {
            TextState("Schedule Delete Title %@".localizeWithFormat(arguments: schedule.name))
        } actions: {
            ButtonState(role: .destructive, action: .confirmDelete(schedule.id)) {
                TextState(ScheduleStrings.text("Schedule Delete"))
            }
            ButtonState(role: .cancel) {
                TextState(ScheduleStrings.text("Cancel"))
            }
        } message: {
            TextState(ScheduleStrings.text("Schedule Delete Message"))
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
            persist(&state)
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

    /// Saves synchronously so snapshots are written in mutation order; never overwrites undecodable data.
    private func persist(_ state: inout State) {
        guard !state.isStorageCorrupted else { return }
        do {
            try storage.save(Array(state.schedules))
            state.saveError = nil
        } catch {
            state.saveError = error.localizedDescription
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
