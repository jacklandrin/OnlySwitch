import ComposableArchitecture
import Foundation
import RemoteCore

/// Edits one schedule draft; the parent decides what saving or discarding means.
@Reducer
public struct ScheduleEditorFeature {
    @ObservableState
    public struct State: Equatable {
        /// `nil` for a new schedule.
        public var original: Schedule?
        public var draft: ScheduleDraft
        public var catalog: [RemoteControlDescriptor]
        public var targetSearch = ""
        public var issues: [ScheduleDraftIssue] = []
        /// Authorization is requested at most once per editor session.
        public var hasRequestedNotificationAuthorization = false
        /// `nil` until the authorization request answers; a denial keeps the toggle on.
        public var isNotificationAuthorized: Bool?

        public init(original: Schedule?, catalog: [RemoteControlDescriptor]) {
            self.original = original
            self.draft = original.map(ScheduleDraft.init) ?? ScheduleDraft()
            self.catalog = catalog
        }

        /// A new draft counts as dirty only once it differs from an empty draft.
        public var isDirty: Bool {
            draft != (original.map(ScheduleDraft.init) ?? ScheduleDraft())
        }

        /// The saved target is missing from a loaded catalog (an empty catalog is treated as not loaded yet).
        public var targetIsUnavailable: Bool {
            guard let original, !catalog.isEmpty else { return false }
            return !catalog.contains { $0.id == original.target.controlID }
        }

        /// Prefers the catalog's current title, so targets saved under another language show translated.
        public var targetTitle: String? {
            catalog.descriptor(for: draft.target)?.title ?? draft.target?.title
        }

        public var allowedActions: [ScheduleAction] {
            draft.target.map { ScheduleAction.allowed(for: $0.behavior) } ?? [.turnOn, .turnOff, .toggle]
        }
    }

    public enum Action: Equatable, BindableAction {
        case binding(BindingAction<State>)
        case targetSelected(RemoteControlID)
        case notificationToggled(Bool)
        case saveTapped
        case discardTapped
        case notificationAuthorization(Bool)
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case save(Schedule)
            case discard
        }
    }

    @Dependency(\.date) private var date
    @Dependency(\.uuid) private var uuid
    @Dependency(\.scheduleNotifications) private var notifications

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding, .delegate:
                return .none

            case let .targetSelected(id):
                guard let descriptor = state.catalog.first(where: { $0.id == id }) else { return .none }
                let previousTitle = state.draft.target?.title
                let name = state.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                state.draft.setTarget(ScheduleTarget(
                    controlID: descriptor.id,
                    title: descriptor.title,
                    behavior: descriptor.behavior
                ))
                if name.isEmpty || name == previousTitle {
                    state.draft.name = descriptor.title
                }
                return .none

            case let .notificationToggled(isOn):
                state.draft.notifies = isOn
                guard isOn, !state.hasRequestedNotificationAuthorization else { return .none }
                state.hasRequestedNotificationAuthorization = true
                return .run { [notifications] send in
                    await send(.notificationAuthorization(await notifications.requestAuthorization()))
                }

            case let .notificationAuthorization(isAuthorized):
                state.isNotificationAuthorized = isAuthorized
                return .none

            case .saveTapped:
                do throws(ScheduleDraftIssues) {
                    let schedule = try state.draft.makeSchedule(original: state.original, id: uuid(), now: date.now)
                    state.issues = []
                    return .send(.delegate(.save(schedule)))
                } catch {
                    state.issues = error.issues
                    return .none
                }

            case .discardTapped:
                return .send(.delegate(.discard))
            }
        }
    }
}
