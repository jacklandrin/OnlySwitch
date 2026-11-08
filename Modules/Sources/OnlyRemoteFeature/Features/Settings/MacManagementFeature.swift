import ComposableArchitecture
import Foundation

@Reducer
struct MacManagementFeature {
    @ObservableState
    struct State: Equatable {
        let mac: PairedMac
        var connectionStatus: MacConnectionStatus
        var isForgetConfirmationPresented = false
        var isForgetting = false
        var issue: Issue?

        init(mac: PairedMac, connectionStatus: MacConnectionStatus = .unknown) {
            self.mac = mac
            self.connectionStatus = connectionStatus
        }
    }

    enum Issue: Equatable, Sendable {
        case forgetFailed

        var message: LocalizedStringResource {
            "OnlySwitch couldn’t remove all local data for this Mac. Retry to finish forgetting it."
        }
    }

    enum OperationResult: Equatable, Sendable { case success, failure }

    enum Action: Equatable {
        case forgetTapped
        case forgetConfirmationDismissed
        case confirmForgetTapped
        case retryForgetTapped
        case forgetResponse(OperationResult)
        case rePairTapped
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case forgotten(UUID)
        case rePair(UUID)
    }

    @Dependency(\.remoteConnection) var connection
    private enum CancelID { case forget }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .forgetTapped:
                guard state.isForgetting == false else { return .none }
                state.isForgetConfirmationPresented = true
                return .none

            case .forgetConfirmationDismissed:
                state.isForgetConfirmationPresented = false
                return .none

            case .confirmForgetTapped, .retryForgetTapped:
                guard state.isForgetting == false else { return .none }
                state.isForgetConfirmationPresented = false
                state.isForgetting = true
                state.issue = nil
                let id = state.mac.id
                return .run { [connection] send in
                    do {
                        try await connection.forgetMac(id)
                        await send(.forgetResponse(.success))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.forgetResponse(.failure))
                    }
                }
                .cancellable(id: CancelID.forget, cancelInFlight: true)

            case .forgetResponse(.failure):
                state.isForgetting = false
                state.issue = .forgetFailed
                return .none

            case .forgetResponse(.success):
                state.isForgetting = false
                return .send(.delegate(.forgotten(state.mac.id)))

            case .rePairTapped:
                return .send(.delegate(.rePair(state.mac.id)))

            case .delegate:
                return .none
            }
        }
    }
}

enum MacConnectionStatus: Equatable, Sendable {
    case unknown
    case connecting
    case connected
    case offline(String?)
    case needsPairing

    var title: LocalizedStringResource {
        switch self {
        case .unknown: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .offline: "Offline"
        case .needsPairing: "Pairing required"
        }
    }
}
