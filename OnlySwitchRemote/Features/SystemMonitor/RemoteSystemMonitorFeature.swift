import ComposableArchitecture
import Foundation
import RemoteCore

@Reducer
struct RemoteSystemMonitorFeature {
    @ObservableState
    struct State: Equatable {
        var selectedMacID: UUID?
        var connectionState: DashboardFeature.ConnectionState = .idle
        var isVisible = false
        var isStreaming = false
        var snapshot: SystemMonitorSnapshot?
        var history = SystemMonitorHistory()
        var expandedMetrics: Set<SystemMonitorMetric> = []
        var availabilityMessage: String?
        var layout: MacSystemMonitorLayout?
    }

    enum Action: Equatable {
        case visibilityChanged(Bool)
        case connectionEvent(RemoteConnectionEvent)
        case toggleExpandedMetric(SystemMonitorMetric)
        case streamingResponse(Result<Bool, RemoteProtocolError>)
        case configureButtonTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case openConfiguration
    }

    @Dependency(\.remoteConnection) private var connection
    private enum CancelID { case streaming }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .configureButtonTapped:
                return .send(.delegate(.openConfiguration))

            case .delegate:
                return .none

            case let .visibilityChanged(isVisible):
                state.isVisible = isVisible
                guard isVisible else {
                    state.isStreaming = false
                    guard state.connectionState == .authenticated else {
                        return .cancel(id: CancelID.streaming)
                    }
                    return setStreaming(false)
                }
                guard state.selectedMacID != nil, state.connectionState == .authenticated else {
                    return .none
                }
                state.availabilityMessage = nil
                return setStreaming(true)

            case let .streamingResponse(.success):
                guard state.isVisible, state.connectionState == .authenticated else { return .none }
                state.isStreaming = true
                return .none

            case let .streamingResponse(.failure(error)):
                state.isStreaming = false
                if error.code == .actionNotSupported || error.code == .upgradeRequired {
                    state.availabilityMessage = String(localized: "This Mac needs a newer OnlySwitch version to share System Monitor.")
                } else {
                    state.availabilityMessage = error.message
                }
                return .none

            case let .toggleExpandedMetric(metric):
                guard metric.supportsDisclosure else { return .none }
                if state.expandedMetrics.contains(metric) {
                    state.expandedMetrics.remove(metric)
                } else {
                    state.expandedMetrics.insert(metric)
                }
                return .none

            case let .connectionEvent(event):
                switch event {
                case let .authenticated(id):
                    guard id == state.selectedMacID else { return .none }
                    state.connectionState = .authenticated
                    guard state.isVisible else { return .none }
                    state.availabilityMessage = nil
                    return setStreaming(true)
                case let .systemMonitor(id, snapshot):
                    guard id == state.selectedMacID,
                          state.isVisible,
                          state.connectionState == .authenticated else { return .none }
                    state.snapshot = snapshot
                    state.history.append(snapshot)
                    return .none
                case let .connecting(id):
                    guard id == state.selectedMacID else { return .none }
                    resetTransientState(&state, connectionState: .connecting)
                case let .offline(id, reason):
                    guard id == state.selectedMacID else { return .none }
                    resetTransientState(&state, connectionState: .offline(reason))
                case let .revoked(id):
                    guard id == state.selectedMacID else { return .none }
                    resetTransientState(&state, connectionState: .revoked)
                case let .sessionStarted(id, _):
                    guard id == state.selectedMacID else { return .none }
                    resetTransientState(&state, connectionState: .connecting)
                case .persistenceRestored, .catalog, .catalogInvalidated, .statusSnapshot, .status, .action, .soundMixer:
                    return .none
                }
                return .cancel(id: CancelID.streaming)
            }
        }
    }

    private func setStreaming(_ enabled: Bool) -> Effect<Action> {
        .run { [connection] send in
            do {
                try await connection.setSystemMonitorStreaming(enabled)
                if enabled { await send(.streamingResponse(.success(true))) }
            } catch let error as RemoteProtocolError {
                if enabled { await send(.streamingResponse(.failure(error))) }
            } catch is CancellationError {
            } catch {
                if enabled {
                    await send(.streamingResponse(.failure(.init(
                        code: .executionFailed,
                        message: String(localized: "System Monitor Unavailable")
                    ))))
                }
            }
        }
        .cancellable(id: CancelID.streaming, cancelInFlight: true)
    }

    private func resetTransientState(
        _ state: inout State,
        connectionState: DashboardFeature.ConnectionState
    ) {
        state.connectionState = connectionState
        state.isStreaming = false
        state.snapshot = nil
        state.history = .init()
        state.expandedMetrics = []
        state.availabilityMessage = nil
    }
}
