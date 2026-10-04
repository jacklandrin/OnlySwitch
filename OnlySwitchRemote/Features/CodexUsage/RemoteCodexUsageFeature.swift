import ComposableArchitecture
import Foundation
import RemoteCore

@Reducer
struct RemoteCodexUsageFeature {
    @ObservableState
    struct State: Equatable {
        var selectedMacID: UUID?
        var authenticatedSessionID: UUID?
        var isVisible = false
        var includeLocalActivity = false
        var snapshot: RemoteCodexUsageSnapshot?
        var isLoading = false
        var activeRequestID: UUID?
        var requestGeneration: UInt64 = 0
        var error: RemoteCodexUsageErrorPresentation?
    }

    enum Action: Equatable {
        case visibilityChanged(Bool)
        case contextChanged(macID: UUID?, sessionID: UUID?)
        case refreshTapped
        case localActivityOptInChanged(Bool)
        case response(generation: UInt64, macID: UUID, sessionID: UUID, requestID: UUID, Result<RemoteCodexUsageResult, RemoteProtocolError>)
        case cancel
    }

    enum CancelID { case request }
    @Dependency(\.remoteConnection) var connection
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .visibilityChanged(visible):
                state.isVisible = visible
                return visible ? load(&state) : cancel(&state)
            case let .contextChanged(macID, sessionID):
                guard state.selectedMacID != macID || state.authenticatedSessionID != sessionID else { return .none }
                let changedMac = state.selectedMacID != macID
                state.selectedMacID = macID
                state.authenticatedSessionID = sessionID
                if changedMac { state.includeLocalActivity = false }
                state.snapshot = nil
                state.error = nil
                let effect = cancel(&state)
                return state.isVisible ? .merge(effect, load(&state)) : effect
            case .refreshTapped:
                return load(&state)
            case let .localActivityOptInChanged(include):
                state.includeLocalActivity = include
                if !include, let snapshot = state.snapshot {
                    state.snapshot = .init(account: snapshot.account, session: snapshot.session, weekly: snapshot.weekly, resetCredits: snapshot.resetCredits, creditBalance: snapshot.creditBalance, source: snapshot.source, fetchedAt: snapshot.fetchedAt, activity: nil)
                }
                return load(&state)
            case let .response(generation, macID, sessionID, requestID, result):
                guard generation == state.requestGeneration,
                      macID == state.selectedMacID,
                      sessionID == state.authenticatedSessionID,
                      requestID == state.activeRequestID else { return .none }
                if case let .success(envelope) = result, envelope.requestID != requestID { return .none }
                state.isLoading = false
                state.activeRequestID = nil
                switch result {
                case let .failure(error): state.error = .init(error)
                case let .success(envelope):
                    guard envelope.requestID == requestID else { return .none }
                    switch envelope.result {
                    case let .success(snapshot): state.snapshot = snapshot; state.error = nil
                    case let .failure(error): state.error = .init(error)
                    }
                }
                return .none
            case .cancel:
                return cancel(&state)
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        guard state.isVisible else { return .none }
        guard let macID = state.selectedMacID, let sessionID = state.authenticatedSessionID else {
            if state.selectedMacID != nil { state.error = .disconnected }
            return .none
        }
        state.requestGeneration &+= 1
        let generation = state.requestGeneration
        let requestID = uuid()
        let request = RemoteCodexUsageRequest(requestID: requestID, includeLocalActivity: state.includeLocalActivity)
        state.activeRequestID = requestID
        state.isLoading = true
        state.error = nil
        return .run { [connection] send in
            let result: Result<RemoteCodexUsageResult, RemoteProtocolError>
            do { result = .success(try await connection.fetchCodexUsage(.init(macID: macID, sessionID: sessionID, request: request))) }
            catch is CancellationError { return }
            catch let error as RemoteProtocolError { result = .failure(error) }
            catch { result = .failure(.init(code: .executionFailed, message: "Codex usage is temporarily unavailable.")) }
            await send(.response(generation: generation, macID: macID, sessionID: sessionID, requestID: requestID, result))
        }.cancellable(id: CancelID.request, cancelInFlight: true)
    }

    private func cancel(_ state: inout State) -> Effect<Action> {
        if state.activeRequestID != nil || state.isLoading { state.requestGeneration &+= 1 }
        state.activeRequestID = nil
        state.isLoading = false
        return .cancel(id: CancelID.request)
    }
}

enum RemoteCodexUsageErrorPresentation: Equatable, Sendable {
    case disconnected, upgradeRequired, authenticationRequired, unavailable, invalidResponse, serverFailure
    init(_ error: RemoteProtocolError) {
        self = switch error.code {
        case .upgradeRequired: .upgradeRequired
        case .authenticationFailed: .authenticationRequired
        case .executionFailed, .requestTimedOut: .unavailable
        case .invalidFrame: .invalidResponse
        default: .serverFailure
        }
    }
    var allowsRetry: Bool { self == .unavailable || self == .invalidResponse || self == .serverFailure }
    var title: String {
        switch self {
        case .disconnected: String(localized: "Mac Disconnected")
        case .upgradeRequired: String(localized: "Update OnlySwitch")
        case .authenticationRequired: String(localized: "Sign In Required")
        case .unavailable: String(localized: "Usage Unavailable")
        case .invalidResponse: String(localized: "Invalid Usage Response")
        case .serverFailure: String(localized: "Couldn’t Load Usage")
        }
    }
    var message: String {
        switch self {
        case .disconnected: String(localized: "Connect to the selected Mac to view Codex usage.")
        case .upgradeRequired: String(localized: "Update OnlySwitch on the selected Mac to use Codex Usage.")
        case .authenticationRequired: String(localized: "Sign in to Codex on the selected Mac, then try again.")
        case .unavailable: String(localized: "Codex usage is temporarily unavailable.")
        case .invalidResponse: String(localized: "The selected Mac returned an invalid usage response.")
        case .serverFailure: String(localized: "OnlySwitch couldn’t load Codex usage from the selected Mac.")
        }
    }
}
