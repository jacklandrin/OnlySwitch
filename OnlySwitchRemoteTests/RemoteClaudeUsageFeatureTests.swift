import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteClaudeUsageFeatureTests {
    @Test func authenticatedRefreshUsesTheCurrentSessionAndCorrelatesSuccess() async {
        let macID = UUID()
        let sessionID = UUID()
        let requestID = UUID()
        let snapshot = RemoteClaudeUsageSnapshot.claudeRemoteFixture
        var initial = RemoteClaudeUsageFeature.State()
        initial.selectedMacID = macID
        initial.authenticatedSessionID = sessionID
        initial.isVisible = true
        let store = TestStore(initialState: initial) { RemoteClaudeUsageFeature() } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.remoteConnection.fetchClaudeUsage = { invocation in
                #expect(invocation.macID == macID)
                #expect(invocation.sessionID == sessionID)
                #expect(invocation.request.requestID == requestID)
                return .init(requestID: requestID, result: .success(snapshot))
            }
        }
        await store.send(.refreshTapped) {
            $0.requestGeneration = 1
            $0.activeRequestID = requestID
            $0.isLoading = true
        }
        await store.receive(.response(generation: 1, macID: macID, sessionID: sessionID, requestID: requestID,
            .success(.init(requestID: requestID, result: .success(snapshot))))) {
            $0.isLoading = false
            $0.activeRequestID = nil
            $0.snapshot = snapshot
        }
    }

    @Test func failedRefreshKeepsTheLastSnapshotAndMarksItStale() async {
        let macID = UUID()
        let sessionID = UUID()
        let requestID = UUID()
        let failure = RemoteProtocolError(code: .executionFailed, message: "Unavailable")
        let snapshot = RemoteClaudeUsageSnapshot.claudeRemoteFixture
        var initial = RemoteClaudeUsageFeature.State()
        initial.selectedMacID = macID
        initial.authenticatedSessionID = sessionID
        initial.isVisible = true
        initial.snapshot = snapshot
        let store = TestStore(initialState: initial) { RemoteClaudeUsageFeature() } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.remoteConnection.fetchClaudeUsage = { _ in throw failure }
        }
        await store.send(.refreshTapped) {
            $0.requestGeneration = 1
            $0.activeRequestID = requestID
            $0.isLoading = true
        }
        await store.receive(.response(generation: 1, macID: macID, sessionID: sessionID, requestID: requestID, .failure(failure))) {
            $0.isLoading = false
            $0.activeRequestID = nil
            $0.isStale = true
            $0.error = .unavailable
        }
        #expect(store.state.snapshot == snapshot)
    }

    @Test func sameMacWithANewSessionClearsThePreviousSnapshot() async {
        let macID = UUID()
        let newSessionID = UUID()
        var initial = RemoteClaudeUsageFeature.State()
        initial.selectedMacID = macID
        initial.authenticatedSessionID = UUID()
        initial.snapshot = .claudeRemoteFixture
        initial.isStale = true
        initial.error = .unavailable
        let store = TestStore(initialState: initial) { RemoteClaudeUsageFeature() }
        await store.send(.contextChanged(macID: macID, sessionID: newSessionID)) {
            $0.authenticatedSessionID = newSessionID
            $0.snapshot = nil
            $0.isStale = false
            $0.error = nil
        }
    }

    @Test func envelopeWithTheWrongRequestIDCannotReplaceTheCurrentSnapshot() async {
        let macID = UUID()
        let sessionID = UUID()
        let requestID = UUID()
        var initial = RemoteClaudeUsageFeature.State()
        initial.selectedMacID = macID
        initial.authenticatedSessionID = sessionID
        initial.activeRequestID = requestID
        initial.isLoading = true
        initial.requestGeneration = 3
        let store = TestStore(initialState: initial) { RemoteClaudeUsageFeature() }
        await store.send(.response(generation: 3, macID: macID, sessionID: sessionID, requestID: requestID,
            .success(.init(requestID: UUID(), result: .success(.claudeRemoteFixture)))))
        #expect(store.state.snapshot == nil)
        #expect(store.state.isLoading)
        #expect(store.state.activeRequestID == requestID)
    }

    @Test func ignoresResponseFromAnOlderContext() async {
        var initial = RemoteClaudeUsageFeature.State()
        initial.selectedMacID = UUID()
        initial.authenticatedSessionID = UUID()
        initial.requestGeneration = 5
        initial.activeRequestID = UUID()
        let store = TestStore(initialState: initial) { RemoteClaudeUsageFeature() }
        await store.send(.response(
            generation: 4,
            macID: UUID(),
            sessionID: UUID(),
            requestID: UUID(),
            .failure(.init(code: .executionFailed, message: "Unavailable"))))
        #expect(store.state.error == nil)
    }

    @Test func changingMacInvalidatesAnOutstandingRequest() async {
        let macID = UUID()
        var initial = RemoteClaudeUsageFeature.State()
        initial.selectedMacID = UUID()
        initial.authenticatedSessionID = UUID()
        initial.requestGeneration = 5
        initial.activeRequestID = UUID()
        initial.isLoading = true
        let store = TestStore(initialState: initial) { RemoteClaudeUsageFeature() }
        await store.send(.contextChanged(macID: macID, sessionID: nil)) {
            $0.selectedMacID = macID
            $0.authenticatedSessionID = nil
            $0.requestGeneration = 6
            $0.activeRequestID = nil
            $0.isLoading = false
        }
        #expect(store.state.snapshot == nil)
    }
}

struct RemoteClaudeUsageLayoutTests {
    @Test func compactAndNarrowLayoutsKeepCardsInOneColumn() {
        #expect(RemoteClaudeUsageLayout.columnCount(availableWidth: 320, horizontalSizeClass: .compact) == 1)
        #expect(RemoteClaudeUsageLayout.columnCount(availableWidth: 1024, horizontalSizeClass: .compact) == 1)
        #expect(RemoteClaudeUsageLayout.columnCount(availableWidth: 640, horizontalSizeClass: .regular) == 1)
        #expect(RemoteClaudeUsageLayout.columnCount(availableWidth: 1024, horizontalSizeClass: .regular) == 2)
    }
}

private extension RemoteClaudeUsageSnapshot {
    static var claudeRemoteFixture: Self {
        .init(account: .init(email: "fixture@example.com", plan: "Max"),
              session: .init(remainingPercent: 75, resetAt: nil),
              weekly: .init(remainingPercent: 50, resetAt: nil),
              models: [], extraUsage: nil, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}

@MainActor
struct RemoteClaudeUsageRootIntegrationTests {
    @Test func selectingClaudePageMakesOnlyClaudeUsageVisible() async {
        let store = TestStore(initialState: RemoteAppFeature.State(hasCompletedInitialSetup: true)) {
            RemoteAppFeature()
        }
        await store.send(.pageSelected(.claudeUsage)) { $0.selectedPage = .claudeUsage }
        await store.receive(.systemMonitor(.visibilityChanged(false)))
        await store.receive(.codexUsage(.visibilityChanged(false)))
        await store.receive(.claudeUsage(.visibilityChanged(true))) { $0.claudeUsage.isVisible = true }
    }

    @Test func staleOtherMacDisconnectKeepsClaudeSession() async {
        let selectedMacID = UUID()
        let sessionID = UUID()
        var initial = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        initial.selectedMacID = selectedMacID
        initial.activeSessionID = sessionID
        initial.claudeUsage.selectedMacID = selectedMacID
        initial.claudeUsage.authenticatedSessionID = sessionID
        let store = TestStore(initialState: initial) { RemoteAppFeature() }
        await store.send(.connectionEvent(.offline(UUID(), "Old connection"))) {
            $0.connectionEventRevision = 1
        }
        #expect(store.state.activeSessionID == sessionID)
        #expect(store.state.claudeUsage.authenticatedSessionID == sessionID)
    }
}
