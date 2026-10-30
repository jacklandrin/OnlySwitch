import ComposableArchitecture
import Foundation
import RemoteCore

@Reducer
struct RemoteBrightnessFeature {
    @ObservableState
    struct State: Equatable {
        var selectedMacID: UUID?
        var connectionState: DashboardFeature.ConnectionState = .idle
        var isVisible = false
        var isEntitled = false
        /// A subscription request was sent and not yet withdrawn; snapshots are accepted from this point.
        var isStreamRequested = false
        var isStreaming = false
        var snapshot: RemoteBrightnessSnapshot?
        var availabilityMessage: String?
        var commandError: String?
        /// Optimistic levels (0...1) for sliders the user is dragging, keyed by display ID.
        var draftLevels: [UInt32: Double] = [:]
        /// Display IDs still being dragged; their drafts survive incoming snapshots.
        var activeDrags: Set<UInt32> = []

        var shouldStream: Bool {
            isVisible && isEntitled && selectedMacID != nil && connectionState == .authenticated
        }

        var canSendCommands: Bool { isStreaming && snapshot != nil }

        func level(for displayID: UInt32) -> Double? {
            draftLevels[displayID] ?? snapshot?.displays.first { $0.id == displayID }?.level
        }
    }

    enum Action: Equatable {
        case visibilityChanged(Bool)
        case entitlementChanged(Bool)
        case connectionEvent(RemoteConnectionEvent)
        case streamingResponse(Result<Bool, RemoteProtocolError>)
        case levelChanged(displayID: UInt32, level: Double)
        case levelCommitted(displayID: UInt32)
        case commandFinished(RemoteProtocolError?)
    }

    static let debounce: Duration = .milliseconds(60)

    @Dependency(\.remoteConnection) private var connection
    @Dependency(\.continuousClock) private var clock
    private enum CancelID: Hashable { case streaming, command(UInt32) }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .visibilityChanged(isVisible):
                state.isVisible = isVisible
                return reconcile(&state)

            case let .entitlementChanged(isEntitled):
                state.isEntitled = isEntitled
                return reconcile(&state)

            case .streamingResponse(.success):
                guard state.isStreamRequested, state.shouldStream else { return .none }
                state.isStreaming = true
                return .none

            case let .streamingResponse(.failure(error)):
                state.isStreaming = false
                if error.code == .upgradeRequired || error.code == .actionNotSupported {
                    state.availabilityMessage = String(localized: "This Mac needs a newer OnlySwitch version to use Brightness.")
                } else {
                    state.availabilityMessage = error.message
                }
                return .none

            case let .connectionEvent(event):
                return handle(event, state: &state)

            case let .levelChanged(displayID, level):
                guard level.isFinite, state.canSendCommands, isControllable(displayID, in: state) else { return .none }
                let level = min(1, max(0, level))
                state.draftLevels[displayID] = level
                state.activeDrags.insert(displayID)
                return send(.setLevel(displayID: displayID, level: level), displayID: displayID, debounced: true)

            case let .levelCommitted(displayID):
                state.activeDrags.remove(displayID)
                guard state.canSendCommands,
                      isControllable(displayID, in: state),
                      let level = state.draftLevels[displayID] else { return .none }
                return send(.setLevel(displayID: displayID, level: level), displayID: displayID, debounced: false)

            case let .commandFinished(error):
                state.commandError = error?.message
                return .none
            }
        }
    }

    private func isControllable(_ displayID: UInt32, in state: State) -> Bool {
        guard let display = state.snapshot?.displays.first(where: { $0.id == displayID }) else { return false }
        return display.control != .unavailable
    }

    private func handle(_ event: RemoteConnectionEvent, state: inout State) -> Effect<Action> {
        switch event {
        case let .authenticated(id):
            guard id == state.selectedMacID else { return .none }
            state.connectionState = .authenticated
            return reconcile(&state)
        case let .brightness(id, snapshot):
            guard id == state.selectedMacID,
                  state.isStreamRequested,
                  snapshot.revision >= state.snapshot?.revision ?? 0 else { return .none }
            apply(snapshot, to: &state)
            return .none
        case let .connecting(id), let .sessionStarted(id, _):
            guard id == state.selectedMacID else { return .none }
            return resetTransientState(&state, connectionState: .connecting)
        case let .offline(id, reason):
            guard id == state.selectedMacID else { return .none }
            return resetTransientState(&state, connectionState: .offline(reason))
        case let .revoked(id):
            guard id == state.selectedMacID else { return .none }
            return resetTransientState(&state, connectionState: .revoked)
        case .persistenceRestored, .catalog, .catalogInvalidated, .statusSnapshot, .status, .action,
             .soundMixer, .systemMonitor, .aphroditeLibraryChanged:
            return .none
        }
    }

    private func apply(_ snapshot: RemoteBrightnessSnapshot, to state: inout State) {
        state.snapshot = snapshot
        let displayIDs = Set(snapshot.displays.map(\.id))
        state.activeDrags.formIntersection(displayIDs)
        state.draftLevels = state.draftLevels.filter { state.activeDrags.contains($0.key) }
    }

    private func reconcile(_ state: inout State) -> Effect<Action> {
        if state.shouldStream {
            guard state.isStreamRequested == false else { return .none }
            state.isStreamRequested = true
            state.availabilityMessage = nil
            return setStreaming(true)
        }
        guard state.isStreamRequested else { return .cancel(id: CancelID.streaming) }
        state.isStreamRequested = false
        state.isStreaming = false
        return state.connectionState == .authenticated ? setStreaming(false) : .cancel(id: CancelID.streaming)
    }

    private func setStreaming(_ enabled: Bool) -> Effect<Action> {
        .run { [connection] send in
            do {
                try await connection.setBrightnessStreaming(enabled)
                if enabled { await send(.streamingResponse(.success(true))) }
            } catch let error as RemoteProtocolError {
                if enabled { await send(.streamingResponse(.failure(error))) }
            } catch is CancellationError {
            } catch {
                if enabled {
                    await send(.streamingResponse(.failure(.init(
                        code: .executionFailed,
                        message: String(localized: "The Mac could not update brightness.")
                    ))))
                }
            }
        }
        .cancellable(id: CancelID.streaming, cancelInFlight: true)
    }

    private func send(_ command: RemoteBrightnessCommand, displayID: UInt32, debounced: Bool) -> Effect<Action> {
        .run { [connection, clock] send in
            if debounced { try await clock.sleep(for: Self.debounce) }
            do {
                try await connection.sendBrightness(command)
                await send(.commandFinished(nil))
            } catch let error as RemoteProtocolError {
                await send(.commandFinished(error))
            } catch is CancellationError {
            } catch {
                await send(.commandFinished(.init(
                    code: .executionFailed,
                    message: String(localized: "The Mac could not update brightness.")
                )))
            }
        } catch: { _, _ in }
        .cancellable(id: CancelID.command(displayID), cancelInFlight: true)
    }

    private func resetTransientState(
        _ state: inout State,
        connectionState: DashboardFeature.ConnectionState
    ) -> Effect<Action> {
        let commandIDs = Set(state.draftLevels.keys).union(state.activeDrags)
        state.connectionState = connectionState
        state.isStreamRequested = false
        state.isStreaming = false
        state.snapshot = nil
        state.draftLevels = [:]
        state.activeDrags = []
        state.availabilityMessage = nil
        state.commandError = nil
        return .merge(
            [.cancel(id: CancelID.streaming)] + commandIDs.map { .cancel(id: CancelID.command($0)) }
        )
    }
}
