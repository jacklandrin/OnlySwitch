import ComposableArchitecture

@Reducer
public struct EqualizerFeature {
    public enum Status: Equatable, Sendable { case flat, pending, waitingForAudio, active, unavailable, unsupported }

    public struct Source: Equatable, Sendable {
        public var id: String
        public var isPersistent: Bool
        public var isSupported: Bool
        public var isAvailable: Bool
        public init(id: String, isPersistent: Bool, isSupported: Bool, isAvailable: Bool) {
            self.id = id; self.isPersistent = isPersistent; self.isSupported = isSupported; self.isAvailable = isAvailable
        }
    }

    public struct App: Equatable, Sendable {
        public var source: Source
        public var settings: EqualizerSettings
        public var isExpanded = false
        public var status: Status = .flat
        public var revision = 0
        public init(source: Source, settings: EqualizerSettings = .flat) { self.source = source; self.settings = settings }
    }

    @ObservableState
    public struct State: Equatable {
        public var apps: [String: App] = [:]
        public var saved: [String: EqualizerSettings] = [:]
        public init() {}
        public func settings(for id: String) -> EqualizerSettings { apps[id]?.settings ?? saved[id] ?? .flat }
    }

    public enum Action: Sendable {
        case load
        case sourcesChanged([Source])
        case toggleExpanded(String)
        case setGain(String, Int, Double)
        case reset(String)
        case applicationResponse(String, Int, Status)
    }

    private struct CancelID: Hashable, Sendable { let appID: String }
    @Dependency(\.equalizerClient) private var client
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
                    var app = state.apps[source.id] ?? App(source: source, settings: state.saved[source.id] ?? .flat)
                    app.source = source
                    app.revision += 1
                    state.apps[source.id] = app
                    effects.append(apply(source.id, state: &state))
                }
                return .merge(effects)
            case .toggleExpanded(let id):
                state.apps[id]?.isExpanded.toggle()
                return .none
            case .setGain(let id, let band, let gain):
                guard var app = state.apps[id], app.source.isSupported, (0..<10).contains(band) else { return .none }
                app.settings.setGain(gain, band: band)
                app.revision += 1
                state.apps[id] = app
                persist(app, state: &state)
                return apply(id, state: &state)
            case .reset(let id):
                guard var app = state.apps[id] else { return .none }
                app.settings = .flat
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
        state.saved[app.source.id] = app.settings.isFlat ? nil : app.settings
        client.save(app.source.id, app.settings)
    }

    private func apply(_ id: String, state: inout State) -> Effect<Action> {
        guard let app = state.apps[id] else { return .none }
        guard app.source.isSupported else { state.apps[id]?.status = .unsupported; return .none }
        guard app.source.isAvailable else { state.apps[id]?.status = .pending; return .none }
        let settings = app.settings, revision = app.revision
        return .run { @MainActor [client] send in
            guard !Task.isCancelled else { return }
            let status = client.apply(id, settings)
            await send(.applicationResponse(id, revision, status))
        }.cancellable(id: CancelID(appID: id), cancelInFlight: true)
    }
}
