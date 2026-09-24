import ComposableArchitecture

@Reducer
public struct SystemMonitorReducer {
    @ObservableState
    public struct State: Equatable {
        public var isVisible = false
        public var enabledMenuBarMetrics: Set<SystemMonitorMetric> = []
        public var expandedMetrics: Set<SystemMonitorMetric> = []
        public var snapshot: SystemMonitorSnapshot?
        public var history = SystemMonitorHistory()
        public var lastFailure: String?
        public var isSampling = false

        public init(
            isVisible: Bool = false,
            enabledMenuBarMetrics: Set<SystemMonitorMetric> = [],
            expandedMetrics: Set<SystemMonitorMetric> = [],
            snapshot: SystemMonitorSnapshot? = nil,
            history: SystemMonitorHistory = SystemMonitorHistory(),
            lastFailure: String? = nil,
            isSampling: Bool = false
        ) {
            self.isVisible = isVisible
            self.enabledMenuBarMetrics = enabledMenuBarMetrics
            self.expandedMetrics = expandedMetrics
            self.snapshot = snapshot
            self.history = history
            self.lastFailure = lastFailure
            self.isSampling = isSampling
        }

        var requiresSampling: Bool {
            isVisible || enabledMenuBarMetrics.isEmpty == false
        }
    }

    public enum Action: Equatable {
        case visibilityChanged(Bool)
        case menuBarMetricsChanged(Set<SystemMonitorMetric>)
        case toggleExpandedMetric(SystemMonitorMetric)
        case snapshotReceived(SystemMonitorSnapshot)
        case streamFailed(String)
        case streamEnded
        case restartRequested
    }

    @Dependency(\.systemMonitor) private var systemMonitor
    @Dependency(\.continuousClock) private var continuousClock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .visibilityChanged(isVisible):
                let wasSampling = state.requiresSampling
                state.isVisible = isVisible
                return samplingEffect(wasSampling: wasSampling, state: &state)

            case let .menuBarMetricsChanged(metrics):
                let wasSampling = state.requiresSampling
                state.enabledMenuBarMetrics = metrics
                return samplingEffect(wasSampling: wasSampling, state: &state)

            case let .toggleExpandedMetric(metric):
                guard metric.supportsDisclosure else { return .none }

                if state.expandedMetrics.contains(metric) {
                    state.expandedMetrics.remove(metric)
                } else {
                    state.expandedMetrics.insert(metric)
                }
                return .none

            case let .snapshotReceived(snapshot):
                state.snapshot = snapshot
                state.history.append(snapshot)
                state.lastFailure = nil
                return .none

            case let .streamFailed(message):
                state.lastFailure = message
                return .none

            case .streamEnded:
                state.isSampling = false
                guard state.requiresSampling else { return .none }
                return scheduleRestart()

            case .restartRequested:
                guard state.requiresSampling, !state.isSampling else { return .none }
                state.isSampling = true
                return samplingStream()
            }
        }
    }

    private func samplingEffect(wasSampling: Bool, state: inout State) -> Effect<Action> {
        if wasSampling, !state.requiresSampling {
            state.isSampling = false
            return .merge(
                .cancel(id: CancelID.sampling),
                .cancel(id: CancelID.restart)
            )
        }

        guard !wasSampling, state.requiresSampling, !state.isSampling else { return .none }
        state.isSampling = true
        return samplingStream()
    }

    private func samplingStream() -> Effect<Action> {
        let systemMonitor = systemMonitor
        return .run { send in
            do {
                for try await snapshot in systemMonitor.snapshots() {
                    try Task.checkCancellation()
                    await send(.snapshotReceived(snapshot))
                }
            } catch is CancellationError {
                // Stopping observation is a normal lifecycle event.
                return
            } catch {
                await send(.streamFailed(error.localizedDescription))
            }
            await send(.streamEnded)
        }
        .cancellable(id: CancelID.sampling, cancelInFlight: true)
    }

    private func scheduleRestart() -> Effect<Action> {
        let continuousClock = continuousClock
        return .run { send in
            do {
                try await continuousClock.sleep(for: .seconds(1))
                await send(.restartRequested)
            } catch is CancellationError {
                // Stopping observation is a normal lifecycle event.
            } catch {
                // Clock failures do not invalidate the last successful snapshot.
            }
        }
        .cancellable(id: CancelID.restart, cancelInFlight: true)
    }

    private enum CancelID {
        case sampling
        case restart
    }
}
