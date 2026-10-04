import ComposableArchitecture
import Testing
@testable import OnlyAgent

@MainActor
struct CodexUsageReducerTests {
    @Test
    func refreshFailureKeepsLastSuccessfulSnapshotAndMarksItStale() async {
        let snapshot = CodexUsageSnapshot.fixture
        let store = TestStore(initialState: CodexUsageReducer.State(snapshot: snapshot)) {
            CodexUsageReducer()
        } withDependencies: {
            $0.codexUsageClient.fetch = { throw CodexUsageError.network }
        }

        await store.send(.refreshTapped) {
            $0.isRefreshing = true
            $0.failureMessage = nil
        }
        await store.receive(\.usageResponse) {
            $0.isRefreshing = false
            $0.failureMessage = "Unable to refresh Codex usage."
            $0.isStale = true
        }
    }

    @Test
    func localActivityLoadsOnlyAfterExplicitUserAction() async {
        let activity = CodexActivityEstimate(
            dailyUsage: [.init(date: .now, tokenCount: 42)],
            isPartial: false
        )
        let store = TestStore(initialState: CodexUsageReducer.State()) {
            CodexUsageReducer()
        } withDependencies: {
            $0.codexLocalUsageClient.scan = { activity }
        }

        #expect(store.state.activity == nil)
        await store.send(.loadLocalActivityTapped) {
            $0.isLoadingActivity = true
        }
        await store.receive(\.localActivityResponse) {
            $0.isLoadingActivity = false
            $0.activity = activity
        }
    }
}

private extension CodexUsageSnapshot {
    static let fixture = CodexUsageSnapshot(
        account: .init(email: "test@example.com", plan: "Plus"),
        session: .init(remainingPercent: 80, resetAt: nil),
        weekly: .init(remainingPercent: 60, resetAt: nil),
        resetCredits: .unavailable,
        source: .oauth,
        fetchedAt: .now
    )
}
