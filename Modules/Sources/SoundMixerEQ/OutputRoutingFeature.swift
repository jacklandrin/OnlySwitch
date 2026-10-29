import ComposableArchitecture

@Reducer
public struct OutputRoutingFeature {
    public enum Status: Equatable, Sendable { case followingSystem, pending, waitingForDevices, partial, active, unsupported, unavailable }
    public typealias Source = EqualizerFeature.Source
    public struct App: Equatable, Sendable {
        public var source: Source
        public var selection: OutputRouteSelection
        public var status: Status = .followingSystem
        public var revision = 0
        public init(source: Source, selection: OutputRouteSelection = .init()) {
            self.source = source; self.selection = selection
        }
    }
    @ObservableState
    public struct State: Equatable {
        public var apps: [String: App] = [:]
        public var saved: [String: OutputRouteSelection] = [:]
        public var devices: [OutputRouteDevice] = []
        /// Session-only labels for unplugged devices; persistence contains UIDs alone.
        public var knownDevices: [String: OutputRouteDevice] = [:]
        public init() {}
        public func selection(for id: String) -> OutputRouteSelection { apps[id]?.selection ?? saved[id] ?? .init() }
    }
    public enum Action: Sendable {
        case load
        case sourcesChanged([Source])
        case devicesChanged([OutputRouteDevice])
        case toggleDevice(String, String)
        case followSystem(String)
        case applicationResponse(String, Int, Status)
    }
    private struct CancelID: Hashable, Sendable { let appID: String }
    @Dependency(\.outputRoutingClient) private var client
    public init() {}
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .load:
                state.saved = client.load()
                return .none
            case .sourcesChanged(let sources):
                let removed = Set(state.apps.keys).subtracting(sources.map(\.id))
                var effects = removed.map { Effect<Action>.cancel(id: CancelID(appID: $0)) }
                state.apps = state.apps.filter { !removed.contains($0.key) }
                for source in sources {
                    var app = state.apps[source.id] ?? App(source: source, selection: state.saved[source.id] ?? .init())
                    app.source = source
                    app.revision += 1
                    state.apps[source.id] = app
                    effects.append(apply(source.id, state: &state))
                }
                return .merge(effects)
            case .devicesChanged(let devices):
                state.devices = devices
                for device in devices { state.knownDevices[device.id] = device }
                var effects: [Effect<Action>] = []
                for id in state.apps.keys.sorted() {
                    state.apps[id]?.revision += 1
                    effects.append(apply(id, state: &state))
                }
                return .merge(effects)
            case .toggleDevice(let id, let uid):
                guard var app = state.apps[id], app.source.isSupported else { return .none }
                let selected = app.selection.deviceUIDs.contains(uid)
                guard selected || state.devices.contains(where: { $0.id == uid }),
                      selected || app.selection.deviceUIDs.count < 16 else { return .none }
                app.selection.toggle(uid)
                app.revision += 1
                state.apps[id] = app
                persist(app, state: &state)
                return apply(id, state: &state)
            case .followSystem(let id):
                guard var app = state.apps[id] else { return .none }
                app.selection = .init()
                app.revision += 1
                state.apps[id] = app
                persist(app, state: &state)
                return apply(id, state: &state)
            case .applicationResponse(let id, let revision, let status):
                guard state.apps[id]?.revision == revision else { return .none }
                state.apps[id]?.status = status
                return .none
            }
        }
    }
    private func persist(_ app: App, state: inout State) {
        guard app.source.isPersistent else { return }
        state.saved[app.source.id] = app.selection.followsSystem ? nil : app.selection
        client.save(app.source.id, app.selection)
    }
    private func apply(_ id: String, state: inout State) -> Effect<Action> {
        guard let app = state.apps[id] else { return .none }
        guard app.source.isSupported else { state.apps[id]?.status = .unsupported; return .none }
        let resolution = OutputRouteResolution(selection: app.selection, devices: state.devices)
        guard app.source.isAvailable else {
            state.apps[id]?.status = resolution.isWaiting ? .waitingForDevices : .pending
            return .none
        }
        // Even an all-offline selection must reach the adapter: it releases any old online chain
        // while retaining the desired UIDs for reconnection.
        let selection = app.selection, revision = app.revision
        return .run { @MainActor [client] send in
            guard !Task.isCancelled else { return }
            let status = client.apply(id, selection)
            await send(.applicationResponse(id, revision, status))
        }.cancellable(id: CancelID(appID: id), cancelInFlight: true)
    }
}
