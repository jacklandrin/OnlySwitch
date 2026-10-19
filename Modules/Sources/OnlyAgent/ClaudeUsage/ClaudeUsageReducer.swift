import ComposableArchitecture
import Foundation

@Reducer
public struct ClaudeUsageReducer {
    @ObservableState
    public struct State: Equatable {
        public var snapshot: ClaudeUsageSnapshot?
        public var isRefreshing = false
        /// True while a user-initiated refresh may show the macOS Keychain password prompt.
        public var isAwaitingKeychainAccess = false
        public var isStale = false
        public var failure: ClaudeUsageError?
        public var signInPhase: ClaudeSignInPhase = .idle
        public var signInFailure: ClaudeSignInFailure?
        public init(snapshot: ClaudeUsageSnapshot? = nil) { self.snapshot = snapshot }

        public var isSigningIn: Bool {
            switch signInPhase {
            case .starting, .waitingForBrowser: true
            case .idle, .succeeded, .failed: false
            }
        }
        /// Claude Code has no usable sign-in, so offer to run `claude auth login`.
        public var canSignIn: Bool { !isSigningIn && (failure == .signedOut || failure == .unauthorized) }
    }
    public enum Action: Equatable {
        case task, refreshTapped, cancel, dismissFailure
        case usageResponse(Result<ClaudeUsageSnapshot, ClaudeUsageError>)
        case signInTapped, cancelSignInTapped
        case signInPhaseChanged(ClaudeSignInPhase)
    }
    @Dependency(\.claudeUsageClient) private var client
    @Dependency(\.claudeCodeSignIn) private var signIn
    private enum CancelID { case refresh, signInObservation }
    public init() {}
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                let observeSignIn: Effect<Action> = .run { [signIn] send in
                    for await phase in await signIn.observe() {
                        // A finished sign-in is handled by exactly one panel.
                        switch phase {
                        case .succeeded, .failed: await signIn.acknowledge()
                        case .idle, .starting, .waitingForBrowser: break
                        }
                        await send(.signInPhaseChanged(phase))
                    }
                }.cancellable(id: CancelID.signInObservation, cancelInFlight: true)
                if state.isRefreshing { return observeSignIn }
                return .merge(refresh(&state, allowPrompt: false), observeSignIn)
            case .refreshTapped:
                state.signInFailure = nil
                return refresh(&state, allowPrompt: true)
            case let .usageResponse(.success(snapshot)):
                state.snapshot = snapshot; state.isRefreshing = false; state.isAwaitingKeychainAccess = false; state.isStale = false; state.failure = nil
                return .none
            case let .usageResponse(.failure(error)):
                state.isRefreshing = false; state.isAwaitingKeychainAccess = false; state.isStale = state.snapshot != nil; state.failure = error
                return .none
            case .cancel:
                state.isRefreshing = false
                state.isAwaitingKeychainAccess = false
                // Only stop observing: the sign-in itself keeps running while the user is in the browser.
                return .merge(.cancel(id: CancelID.refresh), .cancel(id: CancelID.signInObservation))
            case .dismissFailure:
                state.failure = nil
                return .none
            case .signInTapped:
                guard !state.isSigningIn else { return .none }
                state.signInFailure = nil
                state.signInPhase = .starting
                return .run { [signIn] _ in await signIn.start() }
            case .cancelSignInTapped:
                return .run { [signIn] _ in await signIn.cancel() }
            case let .signInPhaseChanged(phase):
                switch phase {
                case .idle, .starting, .waitingForBrowser:
                    state.signInPhase = phase
                    return .none
                case .succeeded:
                    state.signInPhase = .idle
                    state.signInFailure = nil
                    // Claude Code just stored a new credential; reading it may need Keychain approval.
                    return refresh(&state, allowPrompt: true)
                case let .failed(failure):
                    state.signInPhase = .idle
                    state.signInFailure = failure
                    return .none
                }
            }
        }
    }

    private func refresh(_ state: inout State, allowPrompt: Bool) -> Effect<Action> {
        state.isRefreshing = true
        state.isAwaitingKeychainAccess = allowPrompt
        state.failure = nil
        return .run { [client] send in
            do {
                let snapshot = try await client.fetch(allowPrompt)
                try Task.checkCancellation()
                await send(.usageResponse(.success(snapshot)))
            } catch is CancellationError {
                if !Task.isCancelled { await send(.cancel) }
                return
            }
            catch let error as URLError where error.code == .cancelled {
                if !Task.isCancelled { await send(.cancel) }
                return
            }
            catch let error as ClaudeUsageError {
                guard !Task.isCancelled else { return }
                await send(.usageResponse(.failure(error)))
            }
            catch {
                guard !Task.isCancelled else { return }
                await send(.usageResponse(.failure(.network)))
            }
        }.cancellable(id: CancelID.refresh, cancelInFlight: true)
    }
}
