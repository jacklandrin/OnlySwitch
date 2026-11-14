import ComposableArchitecture
import RemoteCore
import Scheduler

/// Edits what clicking the desktop pet does. Choices save immediately; choosing "run a control"
/// keeps the previous action until a control is picked.
@Reducer
struct DesktopPetSettingsFeature {
    enum Mode: Hashable, Sendable {
        case onlyControl
        case control
    }

    @ObservableState
    struct State: Equatable {
        var clickAction: DesktopPetClickAction = .onlyControl
        var mode: Mode = .onlyControl
        var catalog: [RemoteControlDescriptor] = []
        var targetSearch = ""

        var target: ScheduleTarget? { clickAction.target }

        /// The saved control is absent from a loaded catalog (an empty catalog is treated as not loaded yet).
        var isTargetMissing: Bool {
            guard let target, !catalog.isEmpty else { return false }
            return !catalog.contains { $0.id == target.controlID }
        }

        /// Prefers the catalog's current title, so controls saved under another language show translated.
        var targetTitle: String? {
            catalog.descriptor(for: target)?.title ?? target?.title
        }

        var targetDescriptor: RemoteControlDescriptor? {
            catalog.descriptor(for: target)
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case catalogLoaded([RemoteControlDescriptor])
        case targetSelected(RemoteControlID)
    }

    @Dependency(\.desktopPetClickActionStorage) var storage
    @Dependency(\.scheduleExecutor) var executor

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.mode):
                guard state.mode == .onlyControl, state.clickAction != .onlyControl else { return .none }
                state.clickAction = .onlyControl
                return save(.onlyControl)

            case .binding:
                return .none

            case .task:
                state.clickAction = storage.load()
                state.mode = state.target == nil ? .onlyControl : .control
                return .run { [executor] send in
                    await send(.catalogLoaded(await executor.catalog()))
                }

            case let .catalogLoaded(catalog):
                state.catalog = catalog
                return .none

            case let .targetSelected(id):
                guard let descriptor = state.catalog.first(where: { $0.id == id }), descriptor.isAvailable else {
                    return .none
                }
                let action = DesktopPetClickAction.control(
                    ScheduleTarget(controlID: id, title: descriptor.title, behavior: descriptor.behavior)
                )
                state.clickAction = action
                return save(action)
            }
        }
    }

    private func save(_ action: DesktopPetClickAction) -> Effect<Action> {
        .run { [storage] _ in storage.save(action) }
    }
}
