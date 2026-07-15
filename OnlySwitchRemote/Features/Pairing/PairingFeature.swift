import ComposableArchitecture
import Foundation
import RemoteCore

enum PairingIssue: Error, Equatable, Sendable {
    case selectedMacUnavailable
    case invalidCode
    case expired
    case rateLimited
    case revoked
    case upgradeRequired
    case connectionFailed

    var message: String {
        switch self {
        case .selectedMacUnavailable: "The selected Mac is no longer available."
        case .invalidCode: "The pairing code is invalid."
        case .expired: "The pairing code expired."
        case .rateLimited: "Too many pairing attempts."
        case .revoked: "This device was revoked by the Mac."
        case .upgradeRequired: "OnlySwitch must be updated before pairing."
        case .connectionFailed: "The Mac could not be reached."
        }
    }

    var helpText: String {
        switch self {
        case .selectedMacUnavailable: "Wait for the Mac to reappear, then select it again."
        case .invalidCode: "Check the 12-character code shown in OnlySwitch on your Mac and try again."
        case .expired: "Start a new pairing session in OnlySwitch on your Mac and enter its new code."
        case .rateLimited: "Wait a moment, start a new pairing session on the Mac, and try again."
        case .revoked: "Remove this device from OnlySwitch on the Mac, then start a new pairing session."
        case .upgradeRequired: "Install a compatible OnlySwitch version on the Mac or update this app."
        case .connectionFailed: "Make sure both devices are on the same local network and OnlySwitch remote access is enabled."
        }
    }
}

@Reducer
struct PairingFeature {
    @ObservableState
    struct State: Equatable {
        var discoveredMacs: IdentifiedArrayOf<DiscoveredMac> = []
        var selectedMacID: UUID?
        var code = ""
        var isPairing = false
        var issue: PairingIssue?
        var isForegrounded = true
        var isDiscovering = false
        var discoveryGeneration: UInt64 = 0
        var pairingGeneration: UInt64 = 0

        var canPair: Bool {
            isForegrounded
                && isPairing == false
                && code.count == Self.codeLength
                && selectedMacID.flatMap { discoveredMacs[id: $0] } != nil
        }

        var helpText: String {
            if let issue { return issue.helpText }
            if discoveredMacs.isEmpty {
                return "Enable iOS Remote Access and start pairing in OnlySwitch on your Mac."
            }
            if selectedMacID == nil { return "Select a Mac to continue." }
            if code.count < Self.codeLength { return "Enter the 12-character code shown on your Mac." }
            return "Your code stays on this device and is used only for this pairing attempt."
        }

        static let codeLength = 12
    }

    enum Action: Equatable {
        case task
        case discovery(UInt64, DiscoveryEvent)
        case discoveryFinished(UInt64)
        case retryDiscoveryTapped
        case selectMac(UUID)
        case codeChanged(String)
        case pairTapped
        case pairingResponse(UInt64, Result<PairedMac, PairingIssue>)
        case foregroundChanged(Bool)
        case onDisappear
        case cancelTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case paired(PairedMac)
        case cancelled
    }

    @Dependency(\.remoteConnection) var connection

    private enum CancelID { case discovery, pairing }
    private static let allowedCodeCharacters = Set("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.isForegrounded else { return .none }
                state.discoveryGeneration &+= 1
                state.isDiscovering = true
                let generation = state.discoveryGeneration
                return .run { [connection] send in
                    do {
                        for await event in connection.discover() {
                            try Task.checkCancellation()
                            await send(.discovery(generation, event))
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                    }
                    await send(.discoveryFinished(generation))
                }
                .cancellable(id: CancelID.discovery, cancelInFlight: true)

            case let .discovery(generation, event):
                guard generation == state.discoveryGeneration, state.isForegrounded else {
                    return .none
                }
                switch event {
                case let .added(mac):
                    state.discoveredMacs.updateOrAppend(mac)
                case let .removed(id):
                    state.discoveredMacs.remove(id: id)
                    if state.selectedMacID == id {
                        state.selectedMacID = nil
                        state.issue = .selectedMacUnavailable
                    }
                }
                return .none

            case let .discoveryFinished(generation):
                guard generation == state.discoveryGeneration else { return .none }
                state.isDiscovering = false
                return .none

            case .retryDiscoveryTapped:
                return .send(.task)

            case let .selectMac(id):
                guard state.discoveredMacs[id: id] != nil else { return .none }
                state.selectedMacID = id
                state.issue = nil
                return .none

            case let .codeChanged(value):
                state.code = Self.normalize(value)
                state.issue = nil
                return .none

            case .pairTapped:
                guard state.canPair,
                      let id = state.selectedMacID,
                      let mac = state.discoveredMacs[id: id]
                else { return .none }
                state.isPairing = true
                state.issue = nil
                state.pairingGeneration &+= 1
                let generation = state.pairingGeneration
                let code = state.code
                let deviceName = ProcessInfo.processInfo.hostName
                return .run { [connection] send in
                    do {
                        let paired = try await connection.pair(mac, code, deviceName)
                        try Task.checkCancellation()
                        await send(.pairingResponse(generation, .success(paired)))
                    } catch is CancellationError {
                    } catch let error as RemoteProtocolError {
                        await send(.pairingResponse(generation, .failure(Self.issue(for: error))))
                    } catch {
                        await send(.pairingResponse(generation, .failure(.connectionFailed)))
                    }
                }
                .cancellable(id: CancelID.pairing, cancelInFlight: true)

            case let .pairingResponse(generation, result):
                guard generation == state.pairingGeneration,
                      state.isForegrounded,
                      state.isPairing
                else { return .none }
                state.isPairing = false
                switch result {
                case let .success(mac):
                    return .send(.delegate(.paired(mac)))
                case let .failure(issue):
                    state.issue = issue
                    return .none
                }

            case let .foregroundChanged(isForegrounded):
                state.isForegrounded = isForegrounded
                guard isForegrounded else {
                    Self.invalidate(&state)
                    state.discoveredMacs.removeAll()
                    state.selectedMacID = nil
                    return .merge(
                        .cancel(id: CancelID.discovery),
                        .cancel(id: CancelID.pairing)
                    )
                }
                return .send(.task)

            case .onDisappear:
                Self.invalidate(&state)
                return .merge(
                    .cancel(id: CancelID.discovery),
                    .cancel(id: CancelID.pairing)
                )

            case .cancelTapped:
                Self.invalidate(&state)
                return .merge(
                    .cancel(id: CancelID.discovery),
                    .cancel(id: CancelID.pairing),
                    .send(.delegate(.cancelled))
                )

            case .delegate:
                return .none
            }
        }
    }

    private static func normalize(_ value: String) -> String {
        String(
            value.uppercased()
                .filter(allowedCodeCharacters.contains)
                .prefix(State.codeLength)
        )
    }

    private static func invalidate(_ state: inout State) {
        state.discoveryGeneration &+= 1
        state.pairingGeneration &+= 1
        state.isDiscovering = false
        state.isPairing = false
    }

    private static func issue(for error: RemoteProtocolError) -> PairingIssue {
        switch error.code {
        case .pairingExpired: return .expired
        case .pairingRateLimited: return .rateLimited
        case .upgradeRequired: return .upgradeRequired
        case .authenticationFailed:
            return error.message.localizedCaseInsensitiveContains("revok") ? .revoked : .invalidCode
        default: return .connectionFailed
        }
    }
}
