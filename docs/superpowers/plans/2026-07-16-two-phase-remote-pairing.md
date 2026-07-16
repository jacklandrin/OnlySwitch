# OnlySwitch Remote Pairing v1.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make pairing crash-consistent and cancellation-safe across Mac and iOS with a protocol v1.2 prepare/finalize transaction, real catalog preflight, atomic iOS state persistence, and race-free live catalog revisions.

**Architecture:** The Mac retains a provisional credential transaction until an encrypted commit or abort message arrives. The iOS runtime prepares and validates the candidate without disturbing the active session, persists one atomic state envelope, and returns a prepared transaction to PairingFeature; reducer adoption is the commitment gate, after which finalization is resolved idempotently by transaction ID. RemoteCatalogMonitor coalesces refreshes and uses an authentication barrier so advertised and pushed revisions cannot diverge.

**Tech Stack:** Swift 6, SwiftUI, The Composable Architecture, Swift Testing/XCTest, Network.framework, CryptoKit, Security/Keychain, atomic JSON file replacement, iOS/iPadOS 18+, macOS.

## Global Constraints

- Pairing requires negotiated protocol 1.2 transactional-pairing capability; no unsafe legacy fallback.
- Pairing another Mac must leave the active selected session usable until committed finalization.
- No pairing code, credential, proof, decrypted frame, or transaction secret may be logged.
- New protocol messages are encrypted after the existing transcript-bound pairing and authentication proofs.
- Existing frame, payload, catalog-count, icon-size, rate-limit, and resource bounds remain enforced.
- Preserve all current unstaged dashboard, action-lifecycle, refresh-recovery, accessibility, localization, and Mac catalog-monitor changes.
- Prefix shell commands with `rtk`, use `apply_patch` for edits, and never stage `.superpowers/`.

---

### Task 1: RemoteCore v1.2 Transaction Contract

**Files:**
- Modify: `Modules/Sources/RemoteCore/RemoteProtocolVersion.swift`
- Modify: `Modules/Sources/RemoteCore/RemoteMessage.swift`
- Modify: `Modules/Tests/RemoteCoreTests/RemoteCoreTests.swift`

**Interfaces:**
- Produces: `RemoteProtocolVersion.supportsTransactionalPairing`
- Produces: `PairingPrepared`, `PairingTransactionCommand`, `PairingTransactionStatus`, `PairingTransactionState`
- Produces message cases: `.pairingPrepared`, `.pairingCommit`, `.pairingAbort`, `.pairingStatusRequest`, `.pairingStatus`, `.pairingCommitted`

- [ ] **Step 1: Write v1.2 negotiation and message round-trip tests**

```swift
@Test func transactionalPairingRequiresMinorTwo() {
    #expect(!RemoteProtocolVersion(major: 1, minor: 1).supportsTransactionalPairing)
    #expect(RemoteProtocolVersion(major: 1, minor: 2).supportsTransactionalPairing)
    #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 2))
}

@Test func pairingTransactionMessagesRoundTrip() throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000912")!
    let prepared = PairingPrepared(
        transactionID: id,
        macID: UUID(uuidString: "00000000-0000-0000-0000-000000000913")!,
        credential: Data(repeating: 7, count: 32),
        catalogRevision: 4,
        expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    for message in [
        RemoteMessage.pairingPrepared(prepared),
        .pairingCommit(.init(transactionID: id)),
        .pairingAbort(.init(transactionID: id)),
        .pairingStatusRequest(.init(transactionID: id)),
        .pairingStatus(.init(transactionID: id, state: .prepared)),
        .pairingCommitted(.init(transactionID: id)),
    ] {
        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }
}
```

- [ ] **Step 2: Run the focused package tests and observe RED**

Run: `rtk swift test --package-path Modules --filter RemoteCoreTests`

Expected: FAIL because v1.2 transaction types and cases do not exist.

- [ ] **Step 3: Add the protocol types and capability**

```swift
public struct PairingPrepared: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let macID: UUID
    public let credential: Data
    public let catalogRevision: UInt64
    public let expiresAt: Date

    public init(transactionID: UUID, macID: UUID, credential: Data, catalogRevision: UInt64, expiresAt: Date) {
        self.transactionID = transactionID
        self.macID = macID
        self.credential = credential
        self.catalogRevision = catalogRevision
        self.expiresAt = expiresAt
    }
}

public struct PairingTransactionCommand: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public init(transactionID: UUID) { self.transactionID = transactionID }
}

public enum PairingTransactionState: String, Codable, Equatable, Sendable {
    case prepared, committed, aborted
}

public struct PairingTransactionStatus: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let state: PairingTransactionState
    public init(transactionID: UUID, state: PairingTransactionState) {
        self.transactionID = transactionID
        self.state = state
    }
}
```

Set `RemoteProtocolVersion.current` to `1.2`, add `minor >= 2`, and extend `RemoteMessage.Kind`, decoding, and encoding for every new case. Keep v1.0/v1.1 decoding unchanged.

- [ ] **Step 4: Run all Modules tests**

Run: `rtk swift test --package-path Modules`

Expected: 61 existing tests plus the new v1.2 tests pass.

- [ ] **Step 5: Commit Task 1 files only**

```bash
rtk git add Modules/Sources/RemoteCore/RemoteProtocolVersion.swift Modules/Sources/RemoteCore/RemoteMessage.swift Modules/Tests/RemoteCoreTests/RemoteCoreTests.swift
rtk git commit -m "feat: define transactional remote pairing protocol"
```

### Task 2: Mac Provisional Credential Transaction

**Files:**
- Modify: `OnlySwitch/Features/RemoteAccess/Host/RemoteCredentialStore.swift`
- Modify: `OnlySwitch/Features/RemoteAccess/Host/RemotePeerSession.swift`
- Modify: `OnlySwitch/Features/RemoteAccess/Host/RemoteHost.swift`
- Modify: `OnlySwitchTests/RemoteAccess/RemoteHostIntegrationTests.swift`
- Modify: `OnlySwitchTests/RemoteAccess/RemoteHostTestClient.swift`
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 transaction messages.
- Produces: `RemoteCredentialStore.prepareReplacement`, `finalizePrepared`, `abortPrepared`, `transactionStatus`, `recoverExpiredTransactions`.
- Produces: provisional peer state that permits only catalog and transaction operations before commit.

- [ ] **Step 1: Write failing credential-store transaction tests**

```swift
@Test func preparedReplacementDoesNotReplaceCommittedCredential() async throws {
    let store = RemoteCredentialStore.inMemory()
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000920")!
    let old = PairedRemoteDevice(
        id: id, name: "Phone", credential: Data(repeating: 1, count: 32),
        createdAt: .distantPast, lastConnectedAt: nil
    )
    let candidate = PairedRemoteDevice(
        id: id, name: "Phone", credential: Data(repeating: 2, count: 32),
        createdAt: .now, lastConnectedAt: nil
    )
    try await store.save(old)
    let tx = UUID()
    try await store.prepareReplacement(candidate, transactionID: tx, expiresAt: .distantFuture)
    #expect(try await store.load(old.id) == old)
    #expect(try await store.transactionStatus(tx) == .prepared)
    try await store.finalizePrepared(tx)
    #expect(try await store.load(old.id)?.credential == candidate.credential)
    #expect(try await store.transactionStatus(tx) == .committed)
}

@Test func abortAndExpiryRestorePreviousCredentialIdempotently() async throws {
    let store = RemoteCredentialStore.inMemory()
    let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000921")!
    let old = PairedRemoteDevice(
        id: existingID, name: "Phone", credential: Data(repeating: 1, count: 32),
        createdAt: .distantPast, lastConnectedAt: nil
    )
    let replacement = PairedRemoteDevice(
        id: existingID, name: "Phone", credential: Data(repeating: 2, count: 32),
        createdAt: .now, lastConnectedAt: nil
    )
    try await store.save(old)
    let replacementID = UUID()
    try await store.prepareReplacement(replacement, transactionID: replacementID, expiresAt: .distantFuture)
    try await store.abortPrepared(replacementID)
    try await store.abortPrepared(replacementID)
    #expect(try await store.load(existingID) == old)

    let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000922")!
    let newDevice = PairedRemoteDevice(
        id: newID, name: "Tablet", credential: Data(repeating: 3, count: 32),
        createdAt: .now, lastConnectedAt: nil
    )
    let expiringID = UUID()
    try await store.prepareReplacement(
        newDevice,
        transactionID: expiringID,
        expiresAt: Date(timeIntervalSince1970: 10)
    )
    try await store.recoverExpiredTransactions(now: Date(timeIntervalSince1970: 11))
    #expect(try await store.load(newID) == nil)
    #expect(try await store.transactionStatus(expiringID) == .aborted)
}
```

- [ ] **Step 2: Run focused Mac tests and record either RED or the approved scanner baseline**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -derivedDataPath /tmp/OnlySwitchDerivedData test -only-testing:OnlySwitchTests/RemoteHostIntegrationTests`

Expected: RED for missing APIs when the test target compiles; otherwise record only the approved Xcode 26.6 scanner errors.

- [ ] **Step 3: Implement bounded provisional persistence**

Add a persisted record with transaction ID, candidate, previous record, expiry, and state. Use a separate Keychain service/account namespace from committed devices. Bound prepared plus retained committed-status records to 32 entries, evicting only expired/old terminal records.

```swift
func prepareReplacement(
    _ candidate: PairedRemoteDevice,
    transactionID: UUID,
    expiresAt: Date
) throws
func finalizePrepared(_ transactionID: UUID) throws -> PairedRemoteDevice
func abortPrepared(_ transactionID: UUID) throws
func transactionStatus(_ transactionID: UUID) throws -> PairingTransactionState
func recoverExpiredTransactions(now: Date = .now) throws
```

Every method must be idempotent. A mismatched device/transaction returns `.authenticationFailed` without mutating records.

- [ ] **Step 4: Implement provisional peer restrictions and real commit/abort/status**

For negotiated v1.2, pairing proof creates a prepared record and sends `.pairingPrepared`. Candidate authentication verifies the candidate credential without promoting it. The provisional receive loop accepts only:

```swift
case .catalogRequest
case .pairingCommit(command)
case .pairingAbort(command)
case .pairingStatusRequest(command)
case .ping
```

Reject subscription/action/other messages with `.authenticationFailed`. On commit, finalize the store, transition peer state to authenticated, invoke the host authenticated callback, send `.pairingCommitted`, and only then become eligible for normal broadcasts/actions. On abort or deadline, restore and close.

- [ ] **Step 5: Add production integration tests**

Add named tests `prepareDoesNotReplaceCommittedCredential`, `provisionalPeerRejectsAction`, `abortRestoresPreviousCredential`, `commitIsIdempotent`, `lostCommitConfirmationResolvesThroughStatus`, `expiryRecoveryAbortsPreparedRecord`, and `minorOneClientCannotStartTransactionalPairing`. Extend `RemoteHostTestClient` with concrete `preparePairing`, `sendTransaction`, and `receiveTransactionStatus` methods that exchange encrypted wire messages without bypass hooks.

- [ ] **Step 6: Build Mac Release and run focused tests where toolchain permits**

Run: `rtk xcodebuild -quiet -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Release -sdk macosx -derivedDataPath /tmp/OnlySwitchDerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: exit 0.

- [ ] **Step 7: Commit Task 2 files only**

```bash
rtk git add OnlySwitch/Features/RemoteAccess/Host/RemoteCredentialStore.swift OnlySwitch/Features/RemoteAccess/Host/RemotePeerSession.swift OnlySwitch/Features/RemoteAccess/Host/RemoteHost.swift OnlySwitchTests/RemoteAccess/RemoteHostIntegrationTests.swift OnlySwitchTests/RemoteAccess/RemoteHostTestClient.swift OnlySwitch.xcodeproj/project.pbxproj
rtk git commit -m "feat: prepare and finalize Mac pairing transactions"
```

### Task 3: Atomic iOS State Envelope

**Files:**
- Modify: `OnlySwitchRemote/Dependencies/RemotePersistenceClient.swift`
- Modify: `OnlySwitchRemoteTests/RemotePersistenceClientTests.swift`

**Interfaces:**
- Produces: `RemotePersistentStateEnvelope` version 1.
- Produces: `preparePairingState`, `finalizePairingState`, `restorePairingState` as one-envelope atomic transitions.
- Preserves existing `RemotePersistenceClient` reads/writes by routing them through the envelope.

- [ ] **Step 1: Write migration and fault-injection tests**

```swift
@Test func legacyStateMigratesIntoOneEnvelope() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let mac = PairedMac(id: UUID(), displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
    defaults.set(try JSONEncoder().encode([mac]), forKey: "pairedMacs")
    defaults.set(mac.id.uuidString, forKey: "selectedMacID")
    defaults.set(true, forKey: RemotePersistenceClient.initialSetupCompletedKey)
    let store = RemoteFilePersistenceStore(defaults: defaults, rootURL: directory)
    let envelope = try await store.loadEnvelope()
    #expect(envelope.version == 1)
    #expect(envelope.pairedMacs == [mac])
    #expect(envelope.selectedMacID == mac.id)
    #expect(envelope.hasCompletedInitialSetup)
}

@Test func pairingPrepareAndRestoreAreSingleAtomicReplacements() async throws {
    let harness = try AtomicEnvelopeHarness.make()
    let old = PairedMac(id: UUID(), displayName: "Old", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
    let candidate = PairedMac(id: UUID(), displayName: "New", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
    try await harness.store.saveEnvelope(.init(pairedMacs: [old], selectedMacID: old.id, hasCompletedInitialSetup: true))
    let bytesBefore = try Data(contentsOf: harness.envelopeURL)
    harness.failNextReplacement()
    await #expect(throws: (any Error).self) {
        try await harness.store.preparePairingState(candidate, transactionID: UUID(), credentialIdentity: Data(repeating: 8, count: 32))
    }
    #expect(try Data(contentsOf: harness.envelopeURL) == bytesBefore)
    let prepared = try await harness.store.preparePairingState(candidate, transactionID: UUID(), credentialIdentity: Data(repeating: 8, count: 32))
    #expect(try await harness.store.loadEnvelope().selectedMacID == candidate.id)
    try await harness.store.restorePairingState(prepared)
    #expect(try await harness.store.loadEnvelope().selectedMacID == old.id)
}
```

- [ ] **Step 2: Run persistence tests and observe RED**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:OnlySwitchRemoteTests/RemotePersistenceClientTests`

Expected: FAIL because envelope transitions do not exist.

- [ ] **Step 3: Implement the canonical envelope and migration**

```swift
struct RemotePersistentStateEnvelope: Codable, Equatable, Sendable {
    var version: Int = 1
    var pairedMacs: [PairedMac]
    var selectedMacID: UUID?
    var hasCompletedInitialSetup: Bool
    var tombstonedMacIDs: Set<UUID> = []
    var preparedPairing: PreparedPairingPersistenceRecord? = nil

    init(
        pairedMacs: [PairedMac],
        selectedMacID: UUID?,
        hasCompletedInitialSetup: Bool,
        tombstonedMacIDs: Set<UUID> = [],
        preparedPairing: PreparedPairingPersistenceRecord? = nil
    ) {
        self.pairedMacs = pairedMacs
        self.selectedMacID = selectedMacID
        self.hasCompletedInitialSetup = hasCompletedInitialSetup
        self.tombstonedMacIDs = tombstonedMacIDs
        self.preparedPairing = preparedPairing
    }
}

struct RemotePairingRollbackState: Codable, Equatable, Sendable {
    let pairedMacs: [PairedMac]
    let selectedMacID: UUID?
    let hasCompletedInitialSetup: Bool
    let tombstonedMacIDs: Set<UUID>
}

struct PreparedPairingPersistenceRecord: Codable, Equatable, Sendable {
    let transactionID: UUID
    let candidate: PairedMac
    let candidateCredentialIdentity: Data
    let previous: RemotePairingRollbackState
}
```

Write JSON to a sibling temporary file, synchronize/close it, then use atomic replacement. Serialize every envelope mutation inside the file-store actor. Migrate legacy defaults once, preserve legacy files until the envelope replacement succeeds, then mark migration complete.

- [ ] **Step 4: Route every paired/selected/setup/tombstone mutation through the envelope**

Remove the split `commitPairingAndSelect` implementation. Prepare stores the candidate and previous snapshot in one replacement; finalize clears the marker; restore reinstates the marker's previous logical state in one replacement.

- [ ] **Step 5: Run all persistence and root tests**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:OnlySwitchRemoteTests/RemotePersistenceClientTests -only-testing:OnlySwitchRemoteTests/RemoteAppFeatureTests`

Expected: exit 0.

- [ ] **Step 6: Commit Task 3 files only**

```bash
rtk git add OnlySwitchRemote/Dependencies/RemotePersistenceClient.swift OnlySwitchRemoteTests/RemotePersistenceClientTests.swift
rtk git commit -m "feat: persist remote state in an atomic envelope"
```

### Task 4: Prepared Pairing Runtime and TCA Adoption Gate

**Files:**
- Modify: `OnlySwitchRemote/Dependencies/RemoteConnectionClient.swift`
- Modify: `OnlySwitchRemote/Dependencies/RemoteConnectionClient+Live.swift`
- Modify: `OnlySwitchRemote/Features/Pairing/PairingFeature.swift`
- Modify: `OnlySwitchRemote/Features/Pairing/PairingView.swift`
- Modify: `OnlySwitchRemote/Features/Settings/SettingsFeature.swift`
- Modify: `OnlySwitchRemoteTests/RemoteConnectionClientTests.swift`
- Modify: `OnlySwitchRemoteTests/PairingFeatureTests.swift`
- Modify: `OnlySwitchRemoteTests/RemoteEndToEndTests.swift`

**Interfaces:**
- Consumes: Task 1 messages, Task 2 Mac transaction, Task 3 envelope.
- Produces: `PreparedPairing` and dependency methods `preparePairing`, `finalizePairing`, `abortPairing`.
- Keeps existing selected session installed until finalize confirmation.

- [ ] **Step 1: Write failing runtime production-path tests**

Add a `TransactionalLoopbackServer` test harness that uses `RemoteConnectionIO` and `RemoteSessionCrypto`, records received `RemoteMessage` values, and can suspend catalog and commit replies. Then add:

```swift
@Test func prepareAwaitsAndValidatesCatalogWithoutCutover() async throws
@Test func cancelBeforeReducerAdoptionAbortsWithoutEvents() async throws
@Test func finalizeConfirmsThenCutsOverAndClosesOldSession() async throws
@Test func lostCommitReplyResolvesCommittedStatusIdempotently() async throws
@Test func backgroundDuringPrepareRestoresEnvelopeAndCredential() async throws
```

Each test must assert `runtime.snapshot()` still reports the old authenticated Mac before finalize, the server received a real `.catalogRequest`, and the event recorder contains no candidate `.sessionStarted` or `.authenticated` event during prepare.

Assert the old session can still subscribe/send before finalization, no `.sessionStarted`/`.authenticated` candidate event escapes during prepare, and production transport—not an injected catalog gate—supplies the snapshot.

- [ ] **Step 2: Replace the dependency API**

```swift
struct PreparedPairing: Equatable, Sendable {
    let transactionID: UUID
    let mac: PairedMac
    let catalog: RemoteCatalogCache
}

var preparePairing: @Sendable (DiscoveredMac, String, String) async throws -> PreparedPairing
var finalizePairing: @Sendable (UUID) async throws -> PairedMac
var abortPairing: @Sendable (UUID?) async -> Void
```

Delete the ambiguous one-shot `pair`/`cancelPairing` API after all call sites migrate.

- [ ] **Step 3: Implement synchronous catalog preflight**

Before `startReceiving`, candidate session sends `.catalogRequest` and awaits exactly one bounded encrypted `catalogSnapshot`. Validate revision, unique IDs, descriptor count, icon sizes, and that the revision is not older than `PairingPrepared.catalogRevision`. Store this validated cache in `PreparedPairing`.

- [ ] **Step 4: Implement prepare/finalize/abort runtime states**

Keep active `selected/session/sessionToken` untouched during prepare. Serialize Keychain plus envelope preparation. `finalizePairing` sends the same transaction commit, resolves timeout via status query, then atomically finalizes local state, installs candidate, yields ordered session/auth/catalog events, starts receiving, and closes the old session last. `abortPairing` closes candidate, sends abort when possible, and conditionally restores Keychain/envelope.

- [ ] **Step 5: Model reducer adoption as the commitment gate**

PairingFeature receives `.prepared(generation, targetID, PreparedPairing)`. If generation/presentation/foreground checks fail, send abort. If they pass, enter `isFinalizing = true`, make the sheet non-dismissible, and call finalize. Cancel remains available only before this reducer transition. If the app backgrounds while finalizing, the runtime resolves by transaction status and root events remain authoritative.

- [ ] **Step 6: Add end-to-end cancellation-window tests**

Suspend immediately before sending the reducer prepared action, dismiss the sheet, then release and assert abort/no events/no candidate persistence. Separately suspend commit confirmation, verify finalizing UI is non-dismissible, release, and assert one ordered cutover.

- [ ] **Step 7: Run focused and full iOS tests**

Run the focused Pairing/Runtime/E2E suites, then the full OnlySwitchRemote iOS 18.6 suite. Expected: exit 0 and no skipped pairing lifecycle tests.

- [ ] **Step 8: Commit Task 4 files only**

```bash
rtk git add OnlySwitchRemote/Dependencies/RemoteConnectionClient.swift OnlySwitchRemote/Dependencies/RemoteConnectionClient+Live.swift OnlySwitchRemote/Features/Pairing OnlySwitchRemote/Features/Settings/SettingsFeature.swift OnlySwitchRemoteTests/RemoteConnectionClientTests.swift OnlySwitchRemoteTests/PairingFeatureTests.swift OnlySwitchRemoteTests/RemoteEndToEndTests.swift
rtk git commit -m "feat: finalize pairing after reducer adoption"
```

### Task 5: Race-Free Catalog Monitor and Authentication Barrier

**Files:**
- Modify: `OnlySwitch/Features/RemoteAccess/Host/RemoteCatalogMonitor.swift`
- Modify: `OnlySwitch/Features/RemoteAccess/Host/RemoteHost.swift`
- Modify: `OnlySwitch/Features/RemoteAccess/Host/RemotePeerSession.swift`
- Modify: `OnlySwitchTests/RemoteAccess/RemoteHostLifecycleTests.swift`
- Modify: `OnlySwitchTests/RemoteAccess/RemoteHostIntegrationTests.swift`

**Interfaces:**
- Produces: single-flight/coalesced `RemoteCatalogMonitor.requestRefresh()`.
- Produces: authentication broadcast barrier and post-auth revision recheck.

- [ ] **Step 1: Write overlapping-refresh and auth-barrier RED tests**

Use injected continuations to complete provider calls out of order:

```swift
@Test func overlappingRefreshCannotPublishOlderCatalogAsNewerRevision() async throws {
    let provider = SuspendedCatalogProvider(initial: [.darkModeDescriptor])
    let monitor = RemoteCatalogMonitor(provider: provider.client, observeNotifications: false)
    #expect(try await monitor.current().revision == 1)
    async let first = monitor.requestRefresh()
    async let second = monitor.requestRefresh()
    await provider.resumeNewest(with: [.muteDescriptor])
    await provider.resumeOldest(with: [.hideDesktopDescriptor])
    _ = try await (first, second)
    let current = try await monitor.current()
    #expect(current.controls == [.muteDescriptor])
    #expect(current.revision == 2)
}
```

Add deterministic tests named `notificationsCoalesceIntoOneFollowUp`, `transientProviderFailureRecoversOnNextTick`, `rapidStopStartCreatesOnePoller`, `stopAwaitsObservationTasks`, and `authenticationRevisionAdvanceAlwaysProducesInvalidation`. Suspend authentication after reading revision 1, publish revision 2, resume, and assert the peer receives authentication revision 1 followed by `catalogChanged(2)`, or directly advertises revision 2—never a silent gap.

- [ ] **Step 2: Implement single-flight refresh coalescing**

Maintain one active refresh task and a Boolean follow-up request. Poll and notification paths call `requestRefresh`; if active, set follow-up and return. On completion, publish only from that task, then run at most one follow-up. Stop cancels and awaits active poll, debounce, observation, and refresh tasks.

- [ ] **Step 3: Implement authentication revision barrier**

Do not increment authenticated monitoring/broadcast eligibility until authentication success ordering is established. Capture advertised snapshot, send authentication result, transition the peer, register authenticated state, then re-read the monitor; if revision advanced, send one `catalogChanged` before normal receive-loop traffic.

- [ ] **Step 4: Verify multi-peer and failed-refresh recovery**

Ensure both peers receive identical revisions, subsequent snapshot matches, no-change refresh is silent, and request failure produces offline/reconnect rather than permanent dashboard gating.

- [ ] **Step 5: Build Mac Release and run available tests**

Expected: Mac Release exit 0; if focused tests hit the approved scanner baseline, record exact errors and confirm no feature diagnostic.

- [ ] **Step 6: Commit Task 5 files only**

```bash
rtk git add OnlySwitch/Features/RemoteAccess/Host/RemoteCatalogMonitor.swift OnlySwitch/Features/RemoteAccess/Host/RemoteHost.swift OnlySwitch/Features/RemoteAccess/Host/RemotePeerSession.swift OnlySwitchTests/RemoteAccess/RemoteHostLifecycleTests.swift OnlySwitchTests/RemoteAccess/RemoteHostIntegrationTests.swift
rtk git commit -m "fix: serialize remote catalog revisions"
```

### Task 6: Integration, Compatibility UI, and Final Verification

**Files:**
- Modify: `OnlySwitchRemote/App/RemoteAppFeature.swift`
- Modify: `OnlySwitchRemote/Features/Dashboard/DashboardFeature.swift`
- Modify: `OnlySwitchRemote/Features/Settings/SettingsFeature.swift`
- Modify: `OnlySwitchRemote/Features/Pairing/PairingFeature.swift`
- Modify: `OnlySwitchRemote/Features/Pairing/PairingView.swift`
- Modify: `OnlySwitchRemoteTests/RemoteAppFeatureTests.swift`
- Modify: `OnlySwitchRemoteTests/DashboardFeatureTests.swift`
- Modify: `OnlySwitchRemoteTests/PairingFeatureTests.swift`
- Modify: `OnlySwitchRemote/Localizable.xcstrings`
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes all prior tasks.
- Produces the merge-ready complete remote feature.

- [ ] **Step 1: Add incompatible-Mac disabled pairing UI**

Discovered protocol 1.0/1.1 Macs remain listed, but the Pair button is disabled and VoiceOver/localized explanation says to update OnlySwitch on the Mac. Add reducer/view-state tests.

- [ ] **Step 2: Run the complete verification matrix serially**

Run:

```bash
rtk swift test --package-path Modules
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=7E3B9522-AAB5-494F-9CBF-D70650D3BF09' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO build
rtk xcodebuild -quiet -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Release -sdk macosx -derivedDataPath /tmp/OnlySwitchDerivedData CODE_SIGNING_ALLOWED=NO build
```

Expected: tests/builds exit 0 except only the user-approved clean-link/scanner baselines, which must contain no new Swift diagnostic.

- [ ] **Step 3: Run security and project audits**

```bash
rtk rg -n 'print\(|debugPrint\(|NSLog|Logger\.|os_log' OnlySwitch/Features/RemoteAccess OnlySwitchRemote Modules/Sources/RemoteCore Modules/Sources/RemoteTransport
rtk plutil -lint OnlySwitch.xcodeproj/project.pbxproj
rtk jq empty OnlySwitchRemote/Localizable.xcstrings
rtk git diff --check
rtk git status --short
```

Expected: no sensitive logging, project/catalog valid, no whitespace errors, `.superpowers/` unstaged.

- [ ] **Step 4: Request independent whole-branch review**

Review `78845ad..HEAD` plus any remaining working-tree diff against both design specs. Fix every Critical/Important finding and re-review until clean.

- [ ] **Step 5: Commit final integration files**

```bash
rtk git add OnlySwitch.xcodeproj/project.pbxproj OnlySwitchRemote/App OnlySwitchRemote/Features OnlySwitchRemote/Localizable.xcstrings OnlySwitchRemoteTests
rtk git commit -m "feat: complete transactional OnlySwitch remote pairing"
```
