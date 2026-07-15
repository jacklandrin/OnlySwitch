import ComposableArchitecture
import Extensions
import Foundation

struct RemoteAccessPreferences: Equatable, Sendable {
    var isEnabled: Bool
    var displayName: String
}

struct RemoteAccessPreferencesClient: Sendable {
    var load: @Sendable () -> RemoteAccessPreferences
    var setEnabled: @Sendable (Bool) async -> Void
    var setDisplayName: @Sendable (String) async -> Void
}

extension RemoteAccessPreferencesClient: DependencyKey {
    static let enabledKey = "remoteAccess.isEnabled"
    static let displayNameKey = "remoteAccess.displayName"

    static var liveValue: Self {
        Self(
            load: {
                let defaults = UserDefaults.standard
                return RemoteAccessPreferences(
                    isEnabled: defaults.bool(forKey: enabledKey),
                    displayName: defaults.string(forKey: displayNameKey) ?? defaultDisplayName
                )
            },
            setEnabled: { UserDefaults.standard.set($0, forKey: enabledKey) },
            setDisplayName: { UserDefaults.standard.set($0, forKey: displayNameKey) }
        )
    }

    static var testValue: Self {
        Self(
            load: { .init(isEnabled: false, displayName: defaultDisplayName) },
            setEnabled: { _ in },
            setDisplayName: { _ in }
        )
    }

    static var defaultDisplayName: String {
        let name = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "OnlySwitch Mac".localized() : name
    }
}

extension DependencyValues {
    var remoteAccessPreferences: RemoteAccessPreferencesClient {
        get { self[RemoteAccessPreferencesClient.self] }
        set { self[RemoteAccessPreferencesClient.self] = newValue }
    }
}

@Reducer
struct RemoteAccessSettingsFeature {
    @ObservableState
    struct State: Equatable {
        struct Device: Equatable, Identifiable, Sendable {
            let id: UUID
            var name: String
            var lastConnectedAt: Date?
        }

        var isEnabled: Bool
        var displayName: String
        var hostStatus: HostStatus = .stopped
        var connectionCount = 0
        var pairingCode: String?
        var pairingExpiresAt: Date?
        var pairingSecondsRemaining = 0
        var isPairingRequestInFlight = false
        var pairedDevices: IdentifiedArrayOf<Device> = []
        var revokingDeviceIDs: Set<UUID> = []
        @Presents var alert: AlertState<Action.Alert>?

        init(
            isEnabled: Bool = false,
            displayName: String = RemoteAccessPreferencesClient.defaultDisplayName
        ) {
            self.isEnabled = isEnabled
            self.displayName = displayName
        }

        init(preferences: RemoteAccessPreferences) {
            self.init(isEnabled: preferences.isEnabled, displayName: preferences.displayName)
        }
    }

    enum Action {
        case task
        case subscribeToHostEvents
        case setEnabled(Bool)
        case hostStarted
        case hostStopped
        case hostFailed(String)
        case displayNameChanged(String)
        case commitDisplayName
        case startPairingTapped
        case pairingStarted(PairingWindow)
        case pairingFailed(String)
        case pairingTick(Date)
        case cancelPairingTapped
        case pairingCancelled
        case hostEvent(RemoteHostEvent)
        case devicesResponse(Result<[PairedRemoteDevice], RemoteAccessSettingsError>)
        case revokeTapped(UUID)
        case revokeResponse(UUID, Result<[PairedRemoteDevice], RemoteAccessSettingsError>)
        case alert(PresentationAction<Alert>)

        enum Alert: Equatable {
            case confirmRevoke(UUID)
        }
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.remoteAccessPreferences) var preferences
    @Dependency(\.remoteHost) var remoteHost

    private enum CancelID: Hashable {
        case eventStream
        case hostOperation
        case pairingRequest
        case pairingTimer
        case displayNameRestart
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                let loadDevices = Effect<Action>.run { send in
                    await send(.devicesResponse(Result {
                        try await remoteHost.pairedDevices()
                    }.mapError(RemoteAccessSettingsError.init)))
                }
                return state.isEnabled
                    ? .merge(loadDevices, .send(.subscribeToHostEvents))
                    : loadDevices

            case .subscribeToHostEvents:
                guard state.isEnabled else { return .cancel(id: CancelID.eventStream) }
                return .run { send in
                    for await event in remoteHost.events() {
                        await send(.hostEvent(event))
                    }
                }
                .cancellable(id: CancelID.eventStream, cancelInFlight: true)

            case let .setEnabled(isEnabled):
                state.isEnabled = isEnabled
                if isEnabled {
                    state.hostStatus = .starting
                    let displayName = normalizedDisplayName(state.displayName)
                    return .merge(
                        .send(.subscribeToHostEvents),
                        startHost(displayName: displayName, persistEnabled: true)
                    )
                }
                state.hostStatus = .stopped
                state.connectionCount = 0
                clearPairing(state: &state)
                return .merge(
                    .cancel(id: CancelID.eventStream),
                    .cancel(id: CancelID.hostOperation),
                    .cancel(id: CancelID.pairingRequest),
                    .cancel(id: CancelID.pairingTimer),
                    .run { send in
                        await preferences.setEnabled(false)
                        await remoteHost.stop()
                        await send(.hostStopped)
                    }
                )

            case .hostStarted:
                return .none

            case .hostStopped:
                if state.isEnabled {
                    state.hostStatus = .starting
                    return startHost(
                        displayName: normalizedDisplayName(state.displayName),
                        persistEnabled: true
                    )
                }
                state.hostStatus = .stopped
                return .none

            case let .hostFailed(message):
                guard state.isEnabled else { return .none }
                state.hostStatus = .failed(message)
                state.alert = .error(message)
                return .none

            case let .displayNameChanged(displayName):
                state.displayName = displayName
                return .run { send in
                    try await clock.sleep(for: .milliseconds(350))
                    await send(.commitDisplayName)
                }
                .cancellable(id: CancelID.displayNameRestart, cancelInFlight: true)

            case .commitDisplayName:
                let displayName = normalizedDisplayName(state.displayName)
                guard state.isEnabled else {
                    return .run { _ in await preferences.setDisplayName(displayName) }
                }
                state.hostStatus = .starting
                return startHost(displayName: displayName, persistDisplayName: true)

            case .startPairingTapped:
                guard state.isEnabled else { return .none }
                state.isPairingRequestInFlight = true
                return .run { send in
                    do {
                        await send(.pairingStarted(try await remoteHost.startPairing()))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.pairingFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.pairingRequest, cancelInFlight: true)

            case let .pairingStarted(window):
                guard state.isEnabled else {
                    return .run { _ in await remoteHost.cancelPairing() }
                }
                state.isPairingRequestInFlight = false
                setPairing(window, state: &state)
                return pairingTimer()

            case let .pairingFailed(message):
                guard state.isEnabled else { return .none }
                state.isPairingRequestInFlight = false
                state.alert = .error(message)
                return .none

            case let .pairingTick(tickDate):
                guard let expiresAt = state.pairingExpiresAt else {
                    return .cancel(id: CancelID.pairingTimer)
                }
                let remaining = max(0, Int(ceil(expiresAt.timeIntervalSince(tickDate))))
                state.pairingSecondsRemaining = remaining
                guard remaining == 0 else { return .none }
                clearPairing(state: &state)
                return .merge(
                    .cancel(id: CancelID.pairingTimer),
                    .run { send in
                        await remoteHost.cancelPairing()
                        await send(.pairingCancelled)
                    }
                )

            case .cancelPairingTapped:
                clearPairing(state: &state)
                return .merge(
                    .cancel(id: CancelID.pairingTimer),
                    .run { send in
                        await remoteHost.cancelPairing()
                        await send(.pairingCancelled)
                    }
                )

            case .pairingCancelled:
                return .none

            case let .hostEvent(event):
                guard state.isEnabled else { return .none }
                switch event {
                case let .statusChanged(status):
                    state.hostStatus = status
                    return .none
                case let .pairingChanged(window):
                    guard let window else {
                        clearPairing(state: &state)
                        return .cancel(id: CancelID.pairingTimer)
                    }
                    setPairing(window, state: &state)
                    return pairingTimer()
                case let .devicesChanged(devices):
                    state.pairedDevices = deviceSummaries(devices)
                    return .none
                case let .connectionCountChanged(count):
                    state.connectionCount = count
                    return .none
                }

            case let .devicesResponse(.success(devices)):
                state.pairedDevices = deviceSummaries(devices)
                return .none

            case let .devicesResponse(.failure(error)):
                state.alert = .error(error.message)
                return .none

            case let .revokeTapped(id):
                guard let device = state.pairedDevices[id: id] else { return .none }
                state.alert = .revokeDevice(id: id, name: device.name)
                return .none

            case let .alert(.presented(.confirmRevoke(id))):
                state.revokingDeviceIDs.insert(id)
                return .run { send in
                    do {
                        try await remoteHost.revoke(id)
                        let devices = try await remoteHost.pairedDevices()
                        await send(.revokeResponse(id, .success(devices)))
                    } catch {
                        await send(.revokeResponse(id, .failure(.init(error))))
                    }
                }

            case let .revokeResponse(id, .success(devices)):
                state.revokingDeviceIDs.remove(id)
                state.pairedDevices = deviceSummaries(devices)
                return .none

            case let .revokeResponse(id, .failure(error)):
                state.revokingDeviceIDs.remove(id)
                state.alert = .error(error.message)
                return .none

            case .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    private func startHost(
        displayName: String,
        persistEnabled: Bool? = nil,
        persistDisplayName: Bool = false
    ) -> Effect<Action> {
        .run { send in
            do {
                try Task.checkCancellation()
                if let persistEnabled {
                    await preferences.setEnabled(persistEnabled)
                }
                if persistDisplayName {
                    await preferences.setDisplayName(displayName)
                }
                try Task.checkCancellation()
                try await remoteHost.start(.init(displayName: displayName))
                try Task.checkCancellation()
                await send(.hostStarted)
            } catch is CancellationError {
                return
            } catch {
                await send(.hostFailed(error.localizedDescription))
            }
        }
        .cancellable(id: CancelID.hostOperation, cancelInFlight: true)
    }

    private func pairingTimer() -> Effect<Action> {
        .run { send in
            for await _ in clock.timer(interval: .seconds(1)) {
                await send(.pairingTick(now))
            }
        }
        .cancellable(id: CancelID.pairingTimer, cancelInFlight: true)
    }

    private func normalizedDisplayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? RemoteAccessPreferencesClient.defaultDisplayName : trimmed
    }

    private func setPairing(_ window: PairingWindow, state: inout State) {
        state.pairingCode = window.code
        state.pairingExpiresAt = window.expiresAt
        state.pairingSecondsRemaining = max(0, Int(ceil(window.expiresAt.timeIntervalSince(now))))
    }

    private func clearPairing(state: inout State) {
        state.pairingCode = nil
        state.pairingExpiresAt = nil
        state.pairingSecondsRemaining = 0
        state.isPairingRequestInFlight = false
    }

    private func deviceSummaries(_ devices: [PairedRemoteDevice]) -> IdentifiedArrayOf<State.Device> {
        IdentifiedArray(uniqueElements: devices.map {
            State.Device(id: $0.id, name: $0.name, lastConnectedAt: $0.lastConnectedAt)
        })
    }
}

struct RemoteAccessSettingsError: Error, Equatable, Sendable {
    let message: String

    init(_ error: Error) {
        message = error.localizedDescription
    }
}

extension AlertState where Action == RemoteAccessSettingsFeature.Action.Alert {
    static func revokeDevice(id: UUID, name: String) -> Self {
        AlertState {
            TextState("Revoke %@?".localizeWithFormat(arguments: name))
        } actions: {
            ButtonState(role: .destructive, action: .confirmRevoke(id)) {
                TextState("Revoke".localized())
            }
            ButtonState(role: .cancel) {
                TextState("Cancel".localized())
            }
        } message: {
            TextState("This device will need to pair with this Mac again.".localized())
        }
    }

    static func error(_ message: String) -> Self {
        AlertState {
            TextState("iOS Remote".localized())
        } actions: {
            ButtonState(role: .cancel) {
                TextState("OK".localized())
            }
        } message: {
            TextState(message)
        }
    }
}
