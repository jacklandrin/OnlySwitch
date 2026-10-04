import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteCodexUsageFeatureTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
    private let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!

    @Test func firstVisibleAuthenticatedContextLoadsWithLocalActivityOff() async {
        let requests = CodexInvocationRecorder()
        var state = RemoteCodexUsageFeature.State()
        state.selectedMacID = macID
        state.authenticatedSessionID = sessionID
        let store = TestStore(initialState: state) { RemoteCodexUsageFeature() } withDependencies: {
            $0.uuid = UUIDGenerator { requestID }
            $0.remoteConnection.fetchCodexUsage = { invocation in
                await requests.record(invocation)
                return .init(requestID: invocation.request.requestID, result: .success(.fixture))
            }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isLoading = true
            $0.requestGeneration = 1
            $0.activeRequestID = requestID
        }
        await store.receive(.response(
            generation: 1,
            macID: macID,
            sessionID: sessionID,
            requestID: requestID,
            .success(.init(requestID: requestID, result: .success(.fixture)))
        )) {
            $0.isLoading = false
            $0.activeRequestID = nil
            $0.snapshot = .fixture
        }
        let invocation = await requests.values.first
        #expect(invocation?.macID == macID)
        #expect(invocation?.sessionID == sessionID)
        #expect(invocation?.request.includeLocalActivity == false)
    }

    @Test func optingInRefreshesAndOptingOutImmediatelyRemovesActivity() async {
        var state = RemoteCodexUsageFeature.State()
        state.selectedMacID = macID
        state.authenticatedSessionID = sessionID
        state.isVisible = true
        state.snapshot = .fixtureWithActivity
        let store = TestStore(initialState: state) { RemoteCodexUsageFeature() } withDependencies: {
            $0.uuid = UUIDGenerator { requestID }
            $0.remoteConnection.fetchCodexUsage = { invocation in
                .init(
                    requestID: invocation.request.requestID,
                    result: .success(invocation.request.includeLocalActivity ? .fixtureWithActivity : .fixture)
                )
            }
        }

        await store.send(.localActivityOptInChanged(true)) {
            $0.includeLocalActivity = true
            $0.isLoading = true
            $0.requestGeneration = 1
            $0.activeRequestID = requestID
        }
        await store.receive(\.response) {
            $0.isLoading = false
            $0.activeRequestID = nil
            $0.snapshot = .fixtureWithActivity
        }

        await store.send(.localActivityOptInChanged(false)) {
            $0.includeLocalActivity = false
            $0.snapshot = .fixture
            $0.isLoading = true
            $0.requestGeneration = 2
            $0.activeRequestID = requestID
        }
        await store.receive(\.response) {
            $0.isLoading = false
            $0.activeRequestID = nil
            $0.snapshot = .fixture
        }
    }

    @Test func contextLossCancelsAndInvalidatesAnInflightRequest() async {
        var state = RemoteCodexUsageFeature.State()
        state.selectedMacID = macID
        state.authenticatedSessionID = sessionID
        state.isVisible = true
        state.isLoading = true
        state.activeRequestID = requestID
        state.requestGeneration = 4
        let store = TestStore(initialState: state) { RemoteCodexUsageFeature() }

        await store.send(.contextChanged(macID: nil, sessionID: nil)) {
            $0.selectedMacID = nil
            $0.authenticatedSessionID = nil
            $0.isLoading = false
            $0.activeRequestID = nil
            $0.requestGeneration = 5
        }
    }

    @Test func staleGenerationMacSessionAndRequestResponsesAreIgnored() async {
        let other = UUID(uuidString: "00000000-0000-0000-0000-000000000699")!
        var state = RemoteCodexUsageFeature.State()
        state.selectedMacID = macID
        state.authenticatedSessionID = sessionID
        state.isVisible = true
        state.isLoading = true
        state.activeRequestID = requestID
        state.requestGeneration = 8
        let store = TestStore(initialState: state) { RemoteCodexUsageFeature() }
        let result = Result<RemoteCodexUsageResult, RemoteProtocolError>.success(
            .init(requestID: requestID, result: .success(.fixture))
        )

        await store.send(.response(generation: 7, macID: macID, sessionID: sessionID, requestID: requestID, result))
        await store.send(.response(generation: 8, macID: other, sessionID: sessionID, requestID: requestID, result))
        await store.send(.response(generation: 8, macID: macID, sessionID: other, requestID: requestID, result))
        await store.send(.response(generation: 8, macID: macID, sessionID: sessionID, requestID: other, result))
        #expect(store.state.snapshot == nil)
        #expect(store.state.isLoading)
    }

    @Test func currentFailurePreservesSnapshotAndPresentsRetryableError() async {
        var state = RemoteCodexUsageFeature.State()
        state.selectedMacID = macID
        state.authenticatedSessionID = sessionID
        state.isVisible = true
        state.snapshot = .fixture
        state.isLoading = true
        state.activeRequestID = requestID
        state.requestGeneration = 2
        let store = TestStore(initialState: state) { RemoteCodexUsageFeature() }
        let failure = RemoteProtocolError(code: .executionFailed, message: "Codex usage is temporarily unavailable.")

        await store.send(.response(
            generation: 2,
            macID: macID,
            sessionID: sessionID,
            requestID: requestID,
            .failure(failure)
        )) {
            $0.isLoading = false
            $0.activeRequestID = nil
            $0.error = .unavailable
        }
        #expect(store.state.snapshot == .fixture)
        #expect(store.state.error?.allowsRetry == true)
    }

    @Test func unauthenticatedVisibleStateNeverSends() async {
        let requests = CodexInvocationRecorder()
        var state = RemoteCodexUsageFeature.State()
        state.selectedMacID = macID
        let store = TestStore(initialState: state) { RemoteCodexUsageFeature() } withDependencies: {
            $0.remoteConnection.fetchCodexUsage = { invocation in
                await requests.record(invocation)
                throw RemoteProtocolError(code: .authenticationFailed, message: "Unexpected")
            }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.error = .disconnected
        }
        #expect(await requests.values.isEmpty)
    }

    @Test func switchingMacsRequiresFreshLocalActivityOptIn() async {
        let otherMacID = UUID(uuidString: "00000000-0000-0000-0000-000000000604")!
        var state = RemoteCodexUsageFeature.State()
        state.selectedMacID = macID
        state.authenticatedSessionID = sessionID
        state.includeLocalActivity = true
        state.snapshot = .fixtureWithActivity
        let store = TestStore(initialState: state) { RemoteCodexUsageFeature() }

        await store.send(.contextChanged(macID: otherMacID, sessionID: nil)) {
            $0.selectedMacID = otherMacID
            $0.authenticatedSessionID = nil
            $0.includeLocalActivity = false
            $0.snapshot = nil
        }
    }
}

@MainActor
struct RemoteCodexUsageRootIntegrationTests {
    @Test func selectingCodexPageMakesOnlyCodexChildVisible() async {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.selectedPage = .controls
        let store = TestStore(initialState: state) { RemoteAppFeature() }

        await store.send(.pageSelected(.codexUsage)) {
            $0.selectedPage = .codexUsage
        }
        await store.receive(.systemMonitor(.visibilityChanged(false)))
        await store.receive(.codexUsage(.visibilityChanged(true))) {
            $0.codexUsage.isVisible = true
        }
    }

    @Test func authenticatedSessionIdentityIsForwardedToCodexChild() async {
        let macID = UUID(uuidString: "00000000-0000-0000-0000-000000000611")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000612")!
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.selectedMacID = macID
        let store = TestStore(initialState: state) { RemoteAppFeature() }

        await store.send(.connectionEvent(.sessionStarted(macID, sessionID))) {
            $0.activeSessionID = sessionID
            $0.connectionEventRevision = 1
        }
        await store.receive(.codexUsage(.contextChanged(macID: macID, sessionID: sessionID))) {
            $0.codexUsage.selectedMacID = macID
            $0.codexUsage.authenticatedSessionID = sessionID
        }
    }

    @Test func staleOtherMacDisconnectDoesNotClearCurrentCodexSession() async {
        let selectedMacID = UUID(uuidString: "00000000-0000-0000-0000-000000000621")!
        let otherMacID = UUID(uuidString: "00000000-0000-0000-0000-000000000622")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000623")!
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.selectedMacID = selectedMacID
        state.activeSessionID = sessionID
        state.codexUsage.selectedMacID = selectedMacID
        state.codexUsage.authenticatedSessionID = sessionID
        let store = TestStore(initialState: state) { RemoteAppFeature() }

        await store.send(.connectionEvent(.offline(otherMacID, "Stale disconnect"))) {
            $0.connectionEventRevision = 1
        }

        #expect(store.state.activeSessionID == sessionID)
        #expect(store.state.codexUsage.authenticatedSessionID == sessionID)
    }
}

private actor CodexInvocationRecorder {
    private(set) var values: [RemoteCodexUsageInvocation] = []
    func record(_ value: RemoteCodexUsageInvocation) { values.append(value) }
}

private extension RemoteCodexUsageSnapshot {
    static let fixture = Self(
        account: .init(email: "person@example.com", plan: "Plus"),
        session: .init(remainingPercent: 80, resetAt: nil),
        weekly: .init(remainingPercent: 60, resetAt: nil),
        resetCredits: .unavailable,
        creditBalance: .unavailable,
        source: .oauth,
        fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
        activity: nil
    )

    static let fixtureWithActivity = Self(
        account: fixture.account,
        session: fixture.session,
        weekly: fixture.weekly,
        resetCredits: fixture.resetCredits,
        creditBalance: fixture.creditBalance,
        source: fixture.source,
        fetchedAt: fixture.fetchedAt,
        activity: .init(
            dailyUsage: [.init(date: Date(timeIntervalSince1970: 1_800_000_000), tokenCount: 42)],
            isPartial: false
        )
    )
}
