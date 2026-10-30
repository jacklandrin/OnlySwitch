import ComposableArchitecture
import Foundation
import RemoteCore

@Reducer
struct RemoteSoundMixerFeature {
    @ObservableState
    struct State: Equatable {
        var selectedMacID: UUID?
        var connectionState: DashboardFeature.ConnectionState = .idle
        var isVisible = false
        var isEntitled = false
        /// A subscription request was sent and not yet withdrawn; snapshots are accepted from this point.
        var isStreamRequested = false
        var isStreaming = false
        var snapshot: RemoteSoundMixerSnapshot?
        var availabilityMessage: String?
        var commandError: String?
        var expandedAppIDs: Set<String> = []
        /// Optimistic values for sliders the user is dragging; key `RemoteSoundMixerFeature.systemKey` or an app id.
        var draftVolumes: [String: Double] = [:]
        var draftGains: [String: [Int: Double]] = [:]
        /// Slider keys still being dragged; their drafts survive incoming snapshots.
        var activeDrags: Set<String> = []

        var shouldStream: Bool {
            isVisible && isEntitled && selectedMacID != nil && connectionState == .authenticated
        }

        var canSendCommands: Bool { isStreaming && snapshot?.isEnabled == true }

        func volume(for target: String) -> Double? {
            if let draft = draftVolumes[target] { return draft }
            if target == RemoteSoundMixerFeature.systemKey { return snapshot?.systemVolume }
            return snapshot?.apps.first { $0.id == target }?.volume
        }

        func gain(appID: String, band: Int) -> Double {
            if let draft = draftGains[appID]?[band] { return draft }
            let gains = snapshot?.apps.first { $0.id == appID }?.equalizer?.gains ?? []
            return gains.indices.contains(band) ? gains[band] : 0
        }
    }

    enum Action: Equatable {
        case visibilityChanged(Bool)
        case entitlementChanged(Bool)
        case connectionEvent(RemoteConnectionEvent)
        case streamingResponse(Result<Bool, RemoteProtocolError>)
        case volumeChanged(target: String, value: Double)
        case volumeCommitted(target: String)
        case muteToggled(appID: String)
        case expandedToggled(appID: String)
        case gainChanged(appID: String, band: Int, gain: Double)
        case gainCommitted(appID: String, band: Int)
        case equalizerReset(appID: String)
        case outputDeviceToggled(appID: String, deviceID: String)
        case followSystemOutput(appID: String)
        case commandFinished(RemoteProtocolError?)
    }

    static let systemKey = "__system__"
    static let debounce: Duration = .milliseconds(60)

    @Dependency(\.remoteConnection) private var connection
    @Dependency(\.continuousClock) private var clock
    private enum CancelID: Hashable { case streaming, command(String) }

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
                    state.availabilityMessage = String(localized: "This Mac needs a newer OnlySwitch version to use Sound Mixer.")
                } else {
                    state.availabilityMessage = error.message
                }
                return .none

            case let .connectionEvent(event):
                return handle(event, state: &state)

            case let .volumeChanged(target, value):
                guard state.canSendCommands, let command = volumeCommand(target: target, value: value, state: state) else {
                    return .none
                }
                state.draftVolumes[target] = RemoteSoundMixerApp.clampVolume(value)
                state.activeDrags.insert(target)
                return send(command, key: target, debounced: true)

            case let .volumeCommitted(target):
                state.activeDrags.remove(target)
                guard state.canSendCommands,
                      let value = state.draftVolumes[target],
                      let command = volumeCommand(target: target, value: value, state: state) else { return .none }
                return send(command, key: target, debounced: false)

            case let .muteToggled(appID):
                guard state.canSendCommands, let app = app(appID, in: state) else { return .none }
                return send(.setAppMuted(id: appID, isMuted: !app.isMuted), key: "\(appID)#mute", debounced: false)

            case let .expandedToggled(appID):
                if state.expandedAppIDs.remove(appID) == nil {
                    state.expandedAppIDs.insert(appID)
                }
                return .none

            case let .gainChanged(appID, band, gain):
                guard state.canSendCommands,
                      (0 ..< RemoteSoundMixerEqualizer.bandCount).contains(band),
                      let equalizer = app(appID, in: state)?.equalizer,
                      equalizer.status != .unsupported else { return .none }
                let gain = RemoteSoundMixerEqualizer.clampGain(gain)
                state.draftGains[appID, default: [:]][band] = gain
                let key = Self.gainKey(appID: appID, band: band)
                state.activeDrags.insert(key)
                return send(.setAppEqualizerGain(id: appID, band: band, gain: gain), key: key, debounced: true)

            case let .gainCommitted(appID, band):
                let key = Self.gainKey(appID: appID, band: band)
                state.activeDrags.remove(key)
                guard state.canSendCommands, let gain = state.draftGains[appID]?[band] else { return .none }
                return send(.setAppEqualizerGain(id: appID, band: band, gain: gain), key: key, debounced: false)

            case let .equalizerReset(appID):
                guard state.canSendCommands, app(appID, in: state)?.equalizer != nil else { return .none }
                let bandKeys = (0 ..< RemoteSoundMixerEqualizer.bandCount).map { Self.gainKey(appID: appID, band: $0) }
                state.draftGains[appID] = nil
                state.activeDrags.subtract(bandKeys)
                return .merge(
                    .merge(bandKeys.map { .cancel(id: CancelID.command($0)) }),
                    send(.resetAppEqualizer(id: appID), key: "\(appID)#eqreset", debounced: false)
                )

            case let .outputDeviceToggled(appID, deviceID):
                guard state.canSendCommands,
                      let routing = app(appID, in: state)?.routing,
                      state.snapshot?.outputDevices.contains(where: { $0.id == deviceID }) == true
                        || routing.selectedDeviceIDs.contains(deviceID) else { return .none }
                return send(.toggleAppOutputDevice(id: appID, deviceID: deviceID), key: "\(appID)#route", debounced: false)

            case let .followSystemOutput(appID):
                guard state.canSendCommands, app(appID, in: state)?.routing != nil else { return .none }
                return send(.followSystemOutput(id: appID), key: "\(appID)#route", debounced: false)

            case let .commandFinished(error):
                state.commandError = error?.message
                return .none
            }
        }
    }

    private static func gainKey(appID: String, band: Int) -> String { "\(appID)#eq\(band)" }

    private func app(_ id: String, in state: State) -> RemoteSoundMixerApp? {
        state.snapshot?.apps.first { $0.id == id }
    }

    private func volumeCommand(target: String, value: Double, state: State) -> RemoteSoundMixerCommand? {
        let volume = RemoteSoundMixerApp.clampVolume(value)
        if target == Self.systemKey {
            guard state.snapshot?.isSystemVolumeAvailable == true else { return nil }
            return .setSystemVolume(volume)
        }
        guard app(target, in: state) != nil else { return nil }
        return .setAppVolume(id: target, volume: volume)
    }

    private func handle(_ event: RemoteConnectionEvent, state: inout State) -> Effect<Action> {
        switch event {
        case let .authenticated(id):
            guard id == state.selectedMacID else { return .none }
            state.connectionState = .authenticated
            return reconcile(&state)
        case let .soundMixer(id, snapshot):
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
             .systemMonitor, .brightness, .aphroditeLibraryChanged:
            return .none
        }
    }

    private func apply(_ snapshot: RemoteSoundMixerSnapshot, to state: inout State) {
        state.snapshot = snapshot
        let appIDs = Set(snapshot.apps.map(\.id))
        let isKnownTarget = { (target: String) in target == Self.systemKey || appIDs.contains(target) }
        state.activeDrags = state.activeDrags.filter { key in
            isKnownTarget(key.components(separatedBy: "#").first ?? key)
        }
        state.draftVolumes = state.draftVolumes.filter { isKnownTarget($0.key) && state.activeDrags.contains($0.key) }
        state.draftGains = state.draftGains.reduce(into: [:]) { result, entry in
            guard appIDs.contains(entry.key) else { return }
            let bands = entry.value.filter { state.activeDrags.contains(Self.gainKey(appID: entry.key, band: $0.key)) }
            if bands.isEmpty == false { result[entry.key] = bands }
        }
        state.expandedAppIDs.formIntersection(appIDs)
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
                try await connection.setSoundMixerStreaming(enabled)
                if enabled { await send(.streamingResponse(.success(true))) }
            } catch let error as RemoteProtocolError {
                if enabled { await send(.streamingResponse(.failure(error))) }
            } catch is CancellationError {
            } catch {
                if enabled {
                    await send(.streamingResponse(.failure(.init(
                        code: .executionFailed,
                        message: String(localized: "The Mac could not update sound.")
                    ))))
                }
            }
        }
        .cancellable(id: CancelID.streaming, cancelInFlight: true)
    }

    private func send(_ command: RemoteSoundMixerCommand, key: String, debounced: Bool) -> Effect<Action> {
        .run { [connection, clock] send in
            if debounced { try await clock.sleep(for: Self.debounce) }
            do {
                try await connection.sendSoundMixer(command)
                await send(.commandFinished(nil))
            } catch let error as RemoteProtocolError {
                await send(.commandFinished(error))
            } catch is CancellationError {
            } catch {
                await send(.commandFinished(.init(
                    code: .executionFailed,
                    message: String(localized: "The Mac could not update sound.")
                )))
            }
        } catch: { _, _ in }
        .cancellable(id: CancelID.command(key), cancelInFlight: true)
    }

    private func resetTransientState(
        _ state: inout State,
        connectionState: DashboardFeature.ConnectionState
    ) -> Effect<Action> {
        let commandKeys = Set(state.draftVolumes.keys).union(state.activeDrags)
        state.connectionState = connectionState
        state.isStreamRequested = false
        state.isStreaming = false
        state.snapshot = nil
        state.expandedAppIDs = []
        state.draftVolumes = [:]
        state.draftGains = [:]
        state.activeDrags = []
        state.availabilityMessage = nil
        state.commandError = nil
        return .merge(
            [.cancel(id: CancelID.streaming)] + commandKeys.map { .cancel(id: CancelID.command($0)) }
        )
    }
}
