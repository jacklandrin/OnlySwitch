import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlyAgent
@testable import OnlySwitch

struct ClaudeUsageModelsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [(-1.0, 100), (25.4, 75), (100.0, 0), (120.0, 0)])
    func finiteQuotaIsRoundedAndClamped(used: Double, remaining: Int) {
        #expect(ClaudeQuotaWindow.remainingPercent(fromUsedPercent: used) == remaining)
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity])
    func nonfiniteQuotaIsUnavailable(used: Double) {
        #expect(ClaudeQuotaWindow.remainingPercent(fromUsedPercent: used) == nil)
    }

    @Test func malformedSiblingDoesNotDiscardValidWindows() throws {
        let data = Data(#"{"five_hour":{"utilization":25,"resets_at":"2026-10-19T12:00:00.000Z"},"seven_day":{"utilization":"invalid"},"seven_day_sonnet":{"utilization":80,"resets_at":null},"seven_day_opus":null}"#.utf8)
        let value = try ClaudeUsageResponse.decode(data, account: .init(email: nil, plan: "Max"), fetchedAt: now)
        #expect(value.session?.remainingPercent == 75)
        #expect(value.session?.resetAt == Date(timeIntervalSince1970: 1_792_411_200))
        #expect(value.weekly == nil)
        #expect(value.models.map(\.id) == ["seven_day_sonnet"])
        #expect(value.models.first?.quota.remainingPercent == 20)
        #expect(value.fetchedAt == now)
    }

    @Test func nullWindowsRemainUnavailableAndOAuthCentsBecomeCurrencyUnits() throws {
        let data = Data(#"{"five_hour":null,"seven_day":null,"extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":1250,"utilization":25,"currency":"USD"}}"#.utf8)
        let value = try ClaudeUsageResponse.decode(data, account: .init(email: nil, plan: nil), fetchedAt: now)
        #expect(value.session == nil)
        #expect(value.weekly == nil)
        #expect(value.extraUsage?.isEnabled == true)
        #expect(value.extraUsage?.used == 12.5)
        #expect(value.extraUsage?.limit == 50)
        #expect(value.extraUsage?.currency == "USD")
    }

    @Test func currentScopedLimitShapeIsSupported() throws {
        let data = Data(#"{"limits":[{"kind":"weekly_scoped","group":"weekly","percent":30,"resets_at":"2026-10-19T12:00:00Z","scope":{"model":{"id":"sonnet","display_name":"Sonnet"}},"is_active":true},{"kind":"weekly_scoped","group":"weekly","percent":95,"scope":{"model":{"id":"opus","display_name":"Opus"}},"is_active":false}]}"#.utf8)
        let value = try ClaudeUsageResponse.decode(data, account: .init(email: nil, plan: nil), fetchedAt: now)
        #expect(value.models.count == 2)
        #expect(value.models.first(where: { $0.id == "seven_day_sonnet" })?.name == "Sonnet")
        #expect(value.models.first(where: { $0.id == "seven_day_sonnet" })?.quota.remainingPercent == 70)
        #expect(value.models.first(where: { $0.id == "seven_day_opus" })?.quota.remainingPercent == 5)
    }

    @Test func malformedRootFailsInsteadOfInventingQuota() {
        #expect(throws: ClaudeUsageError.invalidResponse) {
            try ClaudeUsageResponse.decode(Data("[]".utf8), account: .init(email: nil, plan: nil), fetchedAt: now)
        }
    }
}

struct ClaudeOAuthCredentialTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func readsClaudeCodeEnvelopeAndMilliseconds() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"fixture-token","expiresAt":1800003600000,"scopes":["user:profile","user:inference"],"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}"#.utf8)
        let credential = try ClaudeOAuthCredential.decode(data, now: now)
        #expect(credential.accessToken == "fixture-token")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(credential.account.plan == "max")
    }

    @Test func expiredTokenRequiresClaudeCodeSignIn() {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"fixture-token","expiresAt":1799999999000,"scopes":["user:profile"]}}"#.utf8)
        #expect(throws: ClaudeUsageError.unauthorized) { try ClaudeOAuthCredential.decode(data, now: now) }
    }

    @Test func expiredFileNeverFallsBackToAnotherKeychainAccount() async {
        let reader = ClaudeOAuthCredentialReader(
            configDirectory: nil,
            homeDirectory: URL(fileURLWithPath: "/fixture/home"),
            readFile: { _ in
                Data(#"{"claudeAiOauth":{"accessToken":"expired-account-token","expiresAt":1799999999000,"scopes":["user:profile"]}}"#.utf8)
            },
            readKeychain: { _, _ in
                Issue.record("An expired signed-in profile must not switch accounts through Keychain fallback.")
                return nil
            }, now: { now })
        await #expect(throws: ClaudeUsageError.unauthorized) {
            try await reader.read(allowKeychainPrompt: false)
        }
    }

    @Test func missingTokenDoesNotBecomeAUsableCredential() {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"","scopes":["user:profile"]}}"#.utf8)
        #expect(throws: ClaudeUsageError.signedOut) { try ClaudeOAuthCredential.decode(data, now: now) }
    }

    @Test func explicitMissingProfileScopeIsRejected() {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"fixture-token","scopes":["user:inference"]}}"#.utf8)
        #expect(throws: ClaudeUsageError.unauthorized) { try ClaudeOAuthCredential.decode(data, now: now) }
    }

    @Test func customConfigNeverFallsBackToTheDefaultKeychainAccount() async {
        let reader = ClaudeOAuthCredentialReader(
            configDirectory: "/fixture/custom-claude",
            homeDirectory: URL(fileURLWithPath: "/fixture/home"),
            readFile: { url in
                #expect(url.path == "/fixture/custom-claude/.credentials.json")
                throw CocoaError(.fileReadNoSuchFile)
            },
            readKeychain: { _, _ in
                Issue.record("A custom profile must not read the default Keychain account.")
                return nil
            }, now: { now })
        await #expect(throws: ClaudeUsageError.signedOut) {
            try await reader.read(allowKeychainPrompt: false)
        }
    }

    @Test(arguments: ["relative-claude-profile", "~/.claude-work"])
    func unsupportedConfigPathNeverReadsTheDefaultAccount(path: String) async {
        let reader = ClaudeOAuthCredentialReader(
            configDirectory: path,
            homeDirectory: URL(fileURLWithPath: "/fixture/home"),
            readFile: { _ in
                Issue.record("An unsupported custom path must not read the default file.")
                throw CocoaError(.fileReadNoSuchFile)
            },
            readKeychain: { _, _ in
                Issue.record("An unsupported custom path must not read the default Keychain account.")
                return nil
            }, now: { now })
        await #expect(throws: ClaudeUsageError.unsupported) {
            try await reader.read(allowKeychainPrompt: false)
        }
    }

    @Test(arguments: [false, true])
    func defaultProfileForwardsTheExplicitKeychainInteractionPolicy(allowPrompt: Bool) async throws {
        let reader = ClaudeOAuthCredentialReader(
            configDirectory: nil,
            homeDirectory: URL(fileURLWithPath: "/fixture/home"),
            readFile: { _ in throw CocoaError(.fileReadNoSuchFile) },
            readKeychain: { service, actualPrompt in
                #expect(service == "Claude Code-credentials")
                #expect(actualPrompt == allowPrompt)
                return Data(#"{"claudeAiOauth":{"accessToken":"fixture-token","scopes":["user:profile"]}}"#.utf8)
            }, now: { now })
        let credential = try await reader.read(allowKeychainPrompt: allowPrompt)
        #expect(credential.accessToken == "fixture-token")
    }

    @Test func deniedKeychainAccessIsReportedWithoutRetry() async {
        let reader = ClaudeOAuthCredentialReader(
            configDirectory: nil,
            homeDirectory: URL(fileURLWithPath: "/fixture/home"),
            readFile: { _ in throw CocoaError(.fileReadNoSuchFile) },
            readKeychain: { _, allowPrompt in
                #expect(allowPrompt == false)
                throw ClaudeUsageError.permissionDenied
            }, now: { now })
        await #expect(throws: ClaudeUsageError.permissionDenied) {
            try await reader.read(allowKeychainPrompt: false)
        }
    }
}

struct ClaudeUsageServiceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [(403, ClaudeUsageError.unauthorized), (429, .rateLimited)])
    func statusMapsToStableError(status: Int, expected: ClaudeUsageError) async {
        let service = ClaudeUsageService(
            credentialClient: .init(read: { allowPrompt in
                #expect(allowPrompt == false)
                return .init(accessToken: "fixture-token", expiresAt: nil, account: .init(email: "fixture@example.com", plan: "Pro"))
            }), transport: { request in
                #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
                #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
                return (Data("upstream-secret-must-not-escape".utf8), response)
            }, now: { now })
        await #expect(throws: expected) { try await service.fetch() }
    }

    @Test func localRefreshCanExplicitlyPermitKeychainInteraction() async throws {
        let service = ClaudeUsageService(
            credentialClient: .init(read: { allowPrompt in
                #expect(allowPrompt)
                return .init(accessToken: "fixture-token", expiresAt: nil, account: .init(email: "fixture@example.com", plan: "Pro"))
            }), transport: { request in
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (Data(#"{"five_hour":{"utilization":20}}"#.utf8), response)
            }, now: { now })
        let snapshot = try await service.fetch(allowKeychainPrompt: true)
        #expect(snapshot.session?.remainingPercent == 80)
    }

    @Test func optionalProfileFailureKeepsSuccessfulUsage() async throws {
        let service = ClaudeUsageService(
            credentialClient: .init(read: { _ in
                .init(accessToken: "fixture-token", expiresAt: nil, account: .init(email: nil, plan: nil))
            }), transport: { request in
                let url = try #require(request.url)
                let isProfile = url.path == "/api/oauth/profile"
                #expect(isProfile || url.path == "/api/oauth/usage")
                let response = try #require(HTTPURLResponse(url: url, statusCode: isProfile ? 500 : 200, httpVersion: nil, headerFields: nil))
                return (Data(#"{"five_hour":{"utilization":20}}"#.utf8), response)
            }, now: { now })
        #expect(try await service.fetch().session?.remainingPercent == 80)
    }

    @Test func transportCancellationIsNotReportedAsNetworkFailure() async {
        let service = ClaudeUsageService(
            credentialClient: .init(read: { _ in
                .init(accessToken: "fixture-token", expiresAt: nil, account: .init(email: nil, plan: nil))
            }), transport: { _ in throw CancellationError() }, now: { now })
        await #expect(throws: CancellationError.self) { try await service.fetch() }
    }

    @Test func optionalProfileURLCancellationIsNotSilentlySwallowed() async {
        let service = ClaudeUsageService(
            credentialClient: .init(read: { _ in
                .init(accessToken: "fixture-token", expiresAt: nil, account: .init(email: nil, plan: nil))
            }), transport: { request in
                let url = try #require(request.url)
                if url.path == "/api/oauth/profile" { throw URLError(.cancelled) }
                #expect(url.path == "/api/oauth/usage")
                let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (Data(#"{"five_hour":{"utilization":20}}"#.utf8), response)
            }, now: { now })
        await #expect(throws: CancellationError.self) { try await service.fetch() }
    }
}

struct ClaudeUsageSessionRenewalTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func expiredSessionIsRenewedByClaudeCodeThenReadAgain() async throws {
        let reads = LockIsolated(0)
        let renewals = LockIsolated(0)
        let service = ClaudeUsageService(
            credentialClient: .init(read: { _ in
                reads.withValue { $0 += 1 }
                if reads.value == 1 { throw ClaudeUsageError.unauthorized }
                return .init(accessToken: "renewed-token", expiresAt: nil, account: .init(email: "fixture@example.com", plan: "Pro"))
            }), transport: { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-token")
                let url = try #require(request.url)
                let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (Data(#"{"five_hour":{"utilization":20}}"#.utf8), response)
            }, now: { now }, renewSession: {
                renewals.withValue { $0 += 1 }
                return true
            })
        #expect(try await service.fetch().session?.remainingPercent == 80)
        #expect(reads.value == 2)
        #expect(renewals.value == 1)
    }

    @Test func unavailableRenewalStillReportsExpiredSession() async {
        let reads = LockIsolated(0)
        let service = ClaudeUsageService(
            credentialClient: .init(read: { _ in
                reads.withValue { $0 += 1 }
                throw ClaudeUsageError.unauthorized
            }), transport: { _ in Issue.record("No request without a credential"); throw ClaudeUsageError.network },
            now: { now }, renewSession: { false })
        await #expect(throws: ClaudeUsageError.unauthorized) { try await service.fetch() }
        #expect(reads.value == 1)
    }

    @Test func renewalIsThrottledPerMinute() async {
        let calls = LockIsolated(0)
        let clock = LockIsolated(Date(timeIntervalSince1970: 0))
        let renewal = ClaudeCodeSessionRenewal(renew: {
            calls.withValue { $0 += 1 }
            return true
        }, now: { clock.value })
        #expect(await renewal.renewIfAllowed())
        #expect(await renewal.renewIfAllowed() == false)
        clock.setValue(Date(timeIntervalSince1970: 61))
        #expect(await renewal.renewIfAllowed())
        #expect(calls.value == 2)
    }
}

struct ClaudeCodeSignInTests {
    @Test func signInSessionReportsBrowserURLThenSuccess() async throws {
        let url = try #require(URL(string: "https://claude.ai/oauth/authorize?code=true"))
        let session = ClaudeCodeSignInSession(signIn: { onWaitingForBrowser in await onWaitingForBrowser(url) })
        let stream = await session.observe()
        await session.start()
        var phases: [ClaudeSignInPhase] = []
        for await phase in stream {
            phases.append(phase)
            if phase == .succeeded { break }
        }
        #expect(phases == [.idle, .starting, .waitingForBrowser(url), .succeeded])
    }

    @Test func missingCLIIsReportedAsFailure() async {
        let session = ClaudeCodeSignInSession(signIn: { _ in throw ClaudeSignInFailure.cliNotFound })
        let stream = await session.observe()
        await session.start()
        var last: ClaudeSignInPhase?
        for await phase in stream {
            last = phase
            if case .failed = phase { break }
        }
        #expect(last == .failed(.cliNotFound))
    }

    @Test func authorizationURLIsFoundInTerminalOutput() {
        let output = "\u{1B}[1mBrowser didn't open? Use the url below:\u{1B}[0m\r\nhttps://claude.ai/oauth/authorize?code=true&client_id=abc&state=xyz\r\n"
        #expect(ClaudeCodeCLI.authorizationURL(in: output)?.absoluteString == "https://claude.ai/oauth/authorize?code=true&client_id=abc&state=xyz")
        #expect(ClaudeCodeCLI.authorizationURL(in: "see https://example.com/oauth/authorize") == nil)
    }

    @Test func terminalEscapesAreRemovedBeforeMatchingPrompts() {
        #expect(ClaudeCodeCLI.stripTerminalEscapes("\u{1B}[2mPress Enter\u{1B}[0m to open") == "Press Enter to open")
    }
}

@MainActor
struct ClaudeUsageReducerTests {
    @Test func transientFailureRetainsLastSuccessfulSnapshotAndMarksStale() async {
        let snapshot = ClaudeUsageSnapshot.claudeTestFixture
        let store = TestStore(initialState: ClaudeUsageReducer.State(snapshot: snapshot)) {
            ClaudeUsageReducer()
        } withDependencies: {
            $0.claudeUsageClient.fetch = { allowPrompt in
                #expect(allowPrompt)
                throw ClaudeUsageError.network
            }
        }
        await store.send(.refreshTapped) {
            $0.isRefreshing = true
            $0.isAwaitingKeychainAccess = true
        }
        await store.receive(\.usageResponse) {
            $0.isRefreshing = false
            $0.isAwaitingKeychainAccess = false
            $0.isStale = true
            $0.failure = .network
        }
        #expect(store.state.snapshot == snapshot)
    }

    @Test func automaticLoadDoesNotPermitKeychainPrompts() async {
        let snapshot = ClaudeUsageSnapshot.claudeTestFixture
        let store = TestStore(initialState: ClaudeUsageReducer.State()) {
            ClaudeUsageReducer()
        } withDependencies: {
            $0.claudeUsageClient.fetch = { allowPrompt in
                #expect(allowPrompt == false)
                return snapshot
            }
        }
        await store.send(.task) { $0.isRefreshing = true }
        await store.receive(\.usageResponse) {
            $0.isRefreshing = false
            $0.snapshot = snapshot
        }
    }

    @Test func cancellingManualRefreshClearsKeychainHint() async {
        let snapshot = ClaudeUsageSnapshot.claudeTestFixture
        let store = TestStore(initialState: ClaudeUsageReducer.State()) {
            ClaudeUsageReducer()
        } withDependencies: {
            $0.claudeUsageClient.fetch = { _ in
                try await Task.sleep(for: .seconds(60))
                return snapshot
            }
        }
        await store.send(.refreshTapped) {
            $0.isRefreshing = true
            $0.isAwaitingKeychainAccess = true
        }
        await store.send(.cancel) {
            $0.isRefreshing = false
            $0.isAwaitingKeychainAccess = false
        }
        await store.finish()
    }

    @Test func signInStartsClaudeCodeLogin() async {
        let started = LockIsolated(false)
        let store = TestStore(initialState: ClaudeUsageReducer.State()) {
            ClaudeUsageReducer()
        } withDependencies: {
            $0.claudeCodeSignIn.start = { started.setValue(true) }
        }
        await store.send(.signInTapped) { $0.signInPhase = .starting }
        await store.finish()
        #expect(started.value)
    }

    @Test func successfulSignInRefreshesAndMayPromptForKeychain() async {
        let snapshot = ClaudeUsageSnapshot.claudeTestFixture
        let store = TestStore(initialState: ClaudeUsageReducer.State()) {
            ClaudeUsageReducer()
        } withDependencies: {
            $0.claudeUsageClient.fetch = { allowPrompt in
                #expect(allowPrompt)
                return snapshot
            }
        }
        await store.send(.signInPhaseChanged(.succeeded)) {
            $0.isRefreshing = true
            $0.isAwaitingKeychainAccess = true
        }
        await store.receive(\.usageResponse) {
            $0.isRefreshing = false
            $0.isAwaitingKeychainAccess = false
            $0.snapshot = snapshot
        }
    }

    @Test func failedSignInIsShownWithoutTouchingUsage() async {
        let store = TestStore(initialState: ClaudeUsageReducer.State()) {
            ClaudeUsageReducer()
        }
        await store.send(.signInPhaseChanged(.waitingForBrowser(nil))) { $0.signInPhase = .waitingForBrowser(nil) }
        await store.send(.signInPhaseChanged(.failed(.timedOut))) {
            $0.signInPhase = .idle
            $0.signInFailure = .timedOut
        }
    }

    @Test func signInIsOfferedOnlyWhenClaudeCodeHasNoUsableSession() {
        var state = ClaudeUsageReducer.State()
        state.failure = .unauthorized
        #expect(state.canSignIn)
        state.failure = .signedOut
        #expect(state.canSignIn)
        state.signInPhase = .starting
        #expect(state.canSignIn == false)
        state.signInPhase = .idle
        state.failure = .network
        #expect(state.canSignIn == false)
    }

    @Test func cancellationStopsRefreshingWithoutReplacingSnapshotOrShowingFailure() async {
        let snapshot = ClaudeUsageSnapshot.claudeTestFixture
        let store = TestStore(initialState: ClaudeUsageReducer.State(snapshot: snapshot)) {
            ClaudeUsageReducer()
        } withDependencies: {
            $0.claudeUsageClient.fetch = { _ in
                try await Task.sleep(for: .seconds(60))
                return snapshot
            }
        }
        await store.send(.task) { $0.isRefreshing = true }
        await store.send(.cancel) { $0.isRefreshing = false }
        await store.finish()
        #expect(store.state.snapshot == snapshot)
        #expect(store.state.failure == nil)
        #expect(store.state.isStale == false)
    }

    @Test func cancelledRequestCannotPublishALateProviderError() async {
        let snapshot = ClaudeUsageSnapshot.claudeTestFixture
        let store = TestStore(initialState: ClaudeUsageReducer.State(snapshot: snapshot)) {
            ClaudeUsageReducer()
        } withDependencies: {
            $0.claudeUsageClient.fetch = { _ in
                do { try await Task.sleep(for: .seconds(60)) }
                catch { throw ClaudeUsageError.network }
                return snapshot
            }
        }
        await store.send(.task) { $0.isRefreshing = true }
        await store.send(.cancel) { $0.isRefreshing = false }
        await store.finish()
        #expect(store.state.failure == nil)
        #expect(store.state.snapshot == snapshot)
    }
}

struct ClaudeUsageRemoteContractTests {
    @Test func olderPeerDoesNotNegotiateClaudeMessages() {
        let current = RemoteProtocolVersion(major: 1, minor: 7)
        #expect(RemoteProtocolVersion.current.supportsClaudeUsageRemote)
        #expect(current.supportsClaudeUsageRemote)
        #expect(current.negotiated(with: .init(major: 1, minor: 6))?.supportsClaudeUsageRemote == false)
    }

    @Test func requestRoundTripsInExistingMessageEnvelope() throws {
        let request = RemoteClaudeUsageRequest(requestID: UUID())
        let message = RemoteMessage.claudeUsageRequest(request)
        let data = try JSONEncoder().encode(message)
        #expect(try JSONDecoder().decode(RemoteMessage.self, from: data) == message)
    }

    @Test func hostProviderNeverPermitsKeychainPrompts() async throws {
        let provider = RemoteClaudeUsageProvider(usageClient: .init(fetch: { allowPrompt in
            #expect(allowPrompt == false)
            return .claudeTestFixture
        }))
        let snapshot = try await provider.fetch().get()
        #expect(snapshot.session?.remainingPercent == 75)
        #expect(snapshot.account.plan == "Pro")
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(encoded.contains("accessToken") == false)
        #expect(encoded.contains("Authorization") == false)
    }
}

@MainActor
struct ClaudeUsageIntegrationTests {
    @Test func switchUpdatesOnlyInjectedVisibility() async throws {
        var visible = true
        let item = ClaudeUsageSwitch(visibility: { visible }, setVisibility: { visible = $0 })
        try await item.operateSwitch(isOn: false)
        #expect(visible == false)
        #expect(await item.currentStatus() == false)
    }

    @Test func sectionAppearsAfterCodexAndCanBeHidden() {
        #expect(SectionBar.sections(authenticator: false, soundMixer: false, systemMonitor: false, codexUsage: true, claudeUsage: true) == [.controls, .codexUsage, .claudeUsage])
        #expect(SectionBar.sections(authenticator: false, soundMixer: false, systemMonitor: false, codexUsage: true, claudeUsage: false) == [.controls, .codexUsage])
    }
}

private extension ClaudeUsageSnapshot {
    static var claudeTestFixture: Self {
        .init(account: .init(email: "fixture@example.com", plan: "Pro"), session: .init(remainingPercent: 75, resetAt: nil), weekly: nil, models: [], extraUsage: nil, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
