#if os(macOS)
import ComposableArchitecture
import Foundation

@Reducer
public struct TailscaleFeature {
    @ObservableState
    public struct State: Equatable {
        public var snapshot: TailscaleSnapshot?
        public var selectedAccountID: String?
        public var error: TailscaleError?
        public var isLoading = false
        public var mutation: TailscaleOperation?
        public var generation = 0
        public var logoutConfirmation = false
        public var logoutAccountID: String?
        public var isCancellingAuthorization = false
        public init() {}
        public var isBusy: Bool { isLoading || mutation != nil || isCancellingAuthorization }
        public var selectedAccount: TailscaleAccount? { snapshot?.accounts.first { $0.id == selectedAccountID } }
        public var canManageSelectedAccount: Bool { selectedAccount?.isActive == true && !isBusy }
    }

    public enum Action: Sendable {
        case appeared, disappeared, refresh
        case selectAccount(String), connectChanged(Bool), addAccount, switchAccount
        case logout, confirmLogout, dismissLogout, renew, cancelLogin
        case preferenceChanged(TailscalePreference, Bool)
        case openApplication, openDownload, externalFailure(TailscaleError)
        case snapshotResponse(Int, Result<TailscaleSnapshot, TailscaleError>)
        case operationCompleted(Int), operationFailed(Int, TailscaleError)
        case authorizationCancelled(Int)
    }
    private enum CancelID { case refresh, mutation, authorizationCancellation }
    @Dependency(\.tailscaleClient) private var client
    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard state.mutation == nil, !state.isCancellingAuthorization else { return .none }
                return refresh(&state)
            case .refresh:
                guard state.mutation == nil, !state.isCancellingAuthorization else { return .none }
                state.error = nil
                return refresh(&state)
            case .disappeared:
                state.isLoading = false; state.logoutConfirmation = false; state.logoutAccountID = nil
                state.isCancellingAuthorization = false
                if state.mutation?.isAuthorization == true {
                    state.generation += 1; state.mutation = nil
                    return .merge(.cancel(id: CancelID.refresh), .cancel(id: CancelID.mutation), .cancel(id: CancelID.authorizationCancellation))
                }
                if state.mutation == nil { state.generation += 1 }
                return .merge(.cancel(id: CancelID.refresh), .cancel(id: CancelID.authorizationCancellation))
            case .selectAccount(let id):
                guard !state.isBusy, !state.logoutConfirmation, state.snapshot?.accounts.contains(where: { $0.id == id }) == true else { return .none }
                state.selectedAccountID = id
                return .none
            case .connectChanged(let connected):
                guard state.snapshot != nil else { return .none }
                return perform(connected ? .connect : .disconnect, state: &state)
            case .addAccount: return perform(.login, state: &state)
            case .switchAccount:
                guard let account = state.selectedAccount, !account.isActive else { return .none }
                return perform(.switchAccount(account.id), state: &state)
            case .logout:
                guard state.canManageSelectedAccount else { return .none }
                state.logoutConfirmation = true
                state.logoutAccountID = state.selectedAccountID
                return .none
            case .dismissLogout:
                state.logoutConfirmation = false; state.logoutAccountID = nil
                return .none
            case .confirmLogout:
                guard state.logoutConfirmation, state.canManageSelectedAccount,
                      let id = state.logoutAccountID, id == state.selectedAccountID else { return .none }
                state.logoutConfirmation = false; state.logoutAccountID = nil
                return perform(.forAccount(id, .logout), state: &state)
            case .renew:
                guard state.canManageSelectedAccount else { return .none }
                return perform(.renew, state: &state)
            case .preferenceChanged(let preference, let enabled):
                guard let snapshot = state.snapshot, snapshot.preferencesAvailable,
                      snapshot.preferences[preference] != nil, !snapshot.connection.requiresAuthentication,
                      preference != .allowLANAccess || snapshot.connection.hasExitNode else { return .none }
                return perform(.setPreference(preference, enabled), state: &state)
            case .cancelLogin:
                guard state.mutation?.isAuthorization == true else { return .none }
                state.generation += 1; state.mutation = nil; state.isCancellingAuthorization = true
                let ticket = state.generation
                // Cancellation owns the actual child until it has exited. Only
                // then read back any account the browser might have authorized.
                return .concatenate(.cancel(id: CancelID.mutation), .run { [client] send in
                    await client.waitForIdle()
                    try Task.checkCancellation()
                    await send(.authorizationCancelled(ticket))
                }.cancellable(id: CancelID.authorizationCancellation))
            case .authorizationCancelled(let ticket):
                guard ticket == state.generation, state.isCancellingAuthorization else { return .none }
                state.isCancellingAuthorization = false
                return refresh(&state)
            case .snapshotResponse(let ticket, let result):
                guard ticket == state.generation, state.mutation == nil else { return .none }
                state.isLoading = false
                switch result {
                case .success(let snapshot):
                    state.snapshot = snapshot
                    if state.logoutAccountID != nil, state.logoutAccountID != snapshot.accounts.first(where: \.isActive)?.id {
                        state.logoutConfirmation = false; state.logoutAccountID = nil
                    }
                    if !snapshot.accounts.contains(where: { $0.id == state.selectedAccountID }) {
                        state.selectedAccountID = snapshot.accounts.first(where: \.isActive)?.id ?? snapshot.accounts.first?.id
                    }
                case .failure(let error): state.error = error
                }
                return .none
            case .operationCompleted(let ticket):
                guard ticket == state.generation else { return .none }
                state.mutation = nil
                return refresh(&state)
            case .operationFailed(let ticket, let error):
                guard ticket == state.generation else { return .none }
                state.mutation = nil; state.error = error
                return refresh(&state)
            case .externalFailure(let error):
                state.error = error
                return .none
            case .openApplication:
                return .run { [client] _ in await client.openApplication() }
            case .openDownload:
                return .run { [client] _ in await client.openDownload() }
            }
        }
    }

    private func refresh(_ state: inout State) -> Effect<Action> {
        state.generation += 1; state.isLoading = true
        let ticket = state.generation
        return .run { [client] send in
            do {
                // A just-dismissed authorization may still be reaping its child.
                await client.waitForIdle()
                try Task.checkCancellation()
                await send(.snapshotResponse(ticket, .success(try await client.snapshot())))
            }
            catch is CancellationError { }
            catch { await send(.snapshotResponse(ticket, .failure(.sanitized(error)))) }
        }.cancellable(id: CancelID.refresh, cancelInFlight: true)
    }
    private func perform(_ operation: TailscaleOperation, state: inout State) -> Effect<Action> {
        guard !state.isBusy, !state.logoutConfirmation else { return .none }
        let scopedOperation: TailscaleOperation
        let intent: TailscaleAccountOperation? = switch operation {
        case .connect: .connect
        case .disconnect: .disconnect
        case .logout: .logout
        case .renew: .renew
        case .setPreference(let preference, let enabled): .setPreference(preference, enabled)
        default: nil
        }
        if let intent {
            guard let id = state.snapshot?.accounts.first(where: \.isActive)?.id else {
                state.error = .authenticationRequired
                return .none
            }
            scopedOperation = .forAccount(id, intent)
        } else { scopedOperation = operation }
        state.generation += 1; state.mutation = scopedOperation; state.error = nil
        let ticket = state.generation
        return .run { [client] send in
            do {
                try await client.perform(scopedOperation)
                try Task.checkCancellation()
                await send(.operationCompleted(ticket))
            } catch is CancellationError { }
            catch { await send(.operationFailed(ticket, .sanitized(error))) }
        }.cancellable(id: CancelID.mutation)
    }
}
#endif
