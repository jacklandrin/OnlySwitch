import ComposableArchitecture
import Extensions
import Foundation

@Reducer
public struct CodexUsageReducer {
    @ObservableState
    public struct State: Equatable {
        public var snapshot: CodexUsageSnapshot?
        public var isRefreshing = false
        public var isLoadingActivity = false
        public var isStale = false
        public var failureMessage: String?
        public var activity: CodexActivityEstimate?

        public init(snapshot: CodexUsageSnapshot? = nil) {
            self.snapshot = snapshot
        }
    }

    public enum Action: Equatable {
        case task
        case refreshTapped
        case usageResponse(Result<CodexUsageSnapshot, CodexUsageError>)
        case loadLocalActivityTapped
        case localActivityResponse(Result<CodexActivityEstimate, CodexUsageError>)
        case dismissFailure
    }

    @Dependency(\.codexUsageClient) private var codexUsageClient
    @Dependency(\.codexLocalUsageClient) private var codexLocalUsageClient

    private enum CancelID { case refresh, activity }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task, .refreshTapped:
                state.isRefreshing = true
                state.failureMessage = nil
                let client = codexUsageClient
                return .run { send in
                    let result: Result<CodexUsageSnapshot, CodexUsageError>
                    do {
                        result = .success(try await client.fetch())
                    } catch let error as CodexUsageError {
                        result = .failure(error)
                    } catch {
                        result = .failure(.network)
                    }
                    await send(.usageResponse(result))
                }
                .cancellable(id: CancelID.refresh, cancelInFlight: true)

            case let .usageResponse(.success(snapshot)):
                state.snapshot = snapshot
                state.isRefreshing = false
                state.isStale = false
                return .none

            case let .usageResponse(.failure(error)):
                state.isRefreshing = false
                state.isStale = state.snapshot != nil
                state.failureMessage = Self.message(for: error)
                return .none

            case .loadLocalActivityTapped:
                state.isLoadingActivity = true
                let client = codexLocalUsageClient
                return .run { send in
                    let result: Result<CodexActivityEstimate, CodexUsageError>
                    do {
                        result = .success(try await client.scan())
                    } catch is CancellationError {
                        return
                    } catch {
                        result = .failure(.network)
                    }
                    await send(.localActivityResponse(result))
                }
                .cancellable(id: CancelID.activity, cancelInFlight: true)

            case let .localActivityResponse(.success(activity)):
                state.activity = activity
                state.isLoadingActivity = false
                return .none

            case .localActivityResponse(.failure):
                state.isLoadingActivity = false
                state.failureMessage = "Unable to read local Codex usage.".localized()
                return .none

            case .dismissFailure:
                state.failureMessage = nil
                return .none
            }
        }
    }

    private static func message(for error: CodexUsageError) -> String {
        switch error {
        case .signedOut: "Sign in to Codex or ChatGPT, then refresh usage.".localized()
        case .unauthorized: "Your Codex session needs to be refreshed.".localized()
        case .network: "Unable to refresh Codex usage.".localized()
        case .invalidResponse: "Codex returned an unreadable usage response.".localized()
        case .unsupported: "No signed-in Codex installation was found.".localized()
        }
    }
}
