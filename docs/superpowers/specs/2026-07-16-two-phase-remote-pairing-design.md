# OnlySwitch Remote Pairing v1.2 Design

## Purpose

OnlySwitch pairing must remain consistent across the Mac, the iOS app, local persistence, UI cancellation, process termination, and network failure. Pairing another Mac must not disturb the currently selected authenticated Mac until the new pairing is fully committed on both devices.

This design replaces the provisional client-only rollback with a protocol-level two-phase transaction. It also closes the catalog-monitor races found during whole-branch review.

## Compatibility

- Add a protocol capability for transactional pairing in RemoteCore protocol version 1.2.
- The iOS app requires this capability before beginning pairing.
- A discovered Mac that lacks it remains visible but pairing is disabled with an explanation that OnlySwitch on the Mac must be updated.
- Existing authenticated protocol behavior remains compatible with negotiated older minor versions. New transactional messages are never sent to a peer that did not negotiate the capability.
- There is no unsafe legacy pairing fallback.

## Pairing Transaction

### Transaction identity

Each attempt has a cryptographically random transaction ID, separate from the transport session ID and device ID. Every prepare, commit, abort, and confirmation message is bound to that transaction ID and the existing transcript-authenticated encrypted session.

### Mac prepare phase

1. The existing pairing-code proof and encrypted authentication proof remain required.
2. The Mac creates a provisional credential record containing:
   - transaction ID;
   - device ID and display name;
   - candidate credential;
   - the previous credential record, if one exists;
   - an expiry deadline.
3. The Mac does not finalize replacement of the previous credential.
4. The provisional secure session can answer catalog requests but is not counted as an authenticated remote-control peer and cannot execute actions.
5. The Mac sends `pairingPrepared`, including the transaction ID and catalog revision.
6. If the transaction expires, disconnects, or receives `pairingAbort`, the Mac restores the previous record or removes the provisional new record.

### iOS validation and durable prepare

1. iOS requests and awaits a full `catalogSnapshot` on the provisional session with a bounded deadline.
2. The snapshot must decode successfully, satisfy frame/icon limits, match the prepared catalog revision or a valid later revision, and contain structurally valid unique control IDs.
3. iOS writes a single versioned state envelope using atomic file replacement. The envelope contains:
   - paired Macs;
   - selected Mac ID;
   - durable tombstones;
   - setup-completion state;
   - a prepared-pairing record with transaction ID, candidate Mac, previous logical state, and candidate credential identity.
4. Keychain storage is updated conditionally. The prepared envelope records enough identity to restore the previous credential without deleting a newer successful pairing.
5. The active selected Mac/session remains installed and usable throughout prepare.

### UI adoption gate

The runtime returns a `PreparedPairing` value rather than publishing a paired Mac. PairingFeature verifies that its generation, target, foreground state, and presentation are still authoritative. Reducer acceptance of that value is the linearized commitment gate: it enters a non-dismissible finalizing state and explicitly calls `finalizePairing(transactionID)`.

Before the reducer accepts the prepared value, Cancel, interactive dismissal, discovery loss, backgrounding, or a superseding pairing calls `abortPairing(transactionID)`. Once finalization starts, the UI no longer offers cancellation; interruption recovery resolves the transaction by ID and completes the outcome idempotently. This defines an achievable distributed commitment point and prevents the previous runtime-publication-before-reducer-adoption race.

### Commit phase

1. iOS sends encrypted `pairingCommit(transactionID)` only after UI adoption.
2. The Mac atomically promotes the provisional credential and replies `pairingCommitted(transactionID)`.
3. If the reply is lost, repeating `pairingCommit` is idempotent and returns the same confirmation.
4. After confirmation, iOS atomically removes the prepared marker from its envelope, installs the new selected session, emits `sessionStarted` then `authenticated`, publishes the validated catalog/status state, and only then closes the previous session.
5. PairingFeature receives the final paired Mac delegate only after runtime finalization succeeds.

### Abort and uncertain outcomes

- Before the reducer commitment gate, abort restores both sides to their previous state.
- A commit timeout does not silently retry with a new transaction. iOS queries transaction status using the same transaction ID.
- Before the commitment gate, `prepared` is aborted when the UI transaction is no longer authoritative. After the gate, `prepared` causes iOS to resend commit.
- `committed` causes iOS to finish local finalization idempotently.
- `aborted` causes iOS to restore its prepared envelope and credential.
- A transaction status that cannot be resolved keeps the old active session selected and presents a retryable pairing error; it never publishes the candidate as paired.

## Mac Persistence and Recovery

The Mac credential store persists provisional transaction state and its previous-record backup. Startup recovery aborts expired prepared transactions. A committed transaction remains idempotently queryable for a bounded retention period so a client can resolve a lost confirmation.

Only a committed credential can authenticate a normal remote-control session. Provisional sessions can perform only pairing commit/abort/status and catalog preflight operations.

## iOS Atomic State Envelope

RemoteFilePersistenceStore migrates legacy paired-Mac, selected-ID, setup, and tombstone state into one versioned JSON envelope. Every mutation reads, transforms, and writes this envelope through a temporary file followed by atomic replacement. In-memory persistence mirrors the same model.

Prepared pairing and rollback are envelope transitions, not sequences of independent UserDefaults writes. Keychain changes remain conditional on the exact credential identity and are serialized with envelope transitions through the existing local-state mutation coordinator.

## Live Catalog Monitoring

- RemoteCatalogMonitor uses a single-flight refresh loop. Concurrent poll and notification requests coalesce into one active load plus at most one follow-up refresh.
- Results from an older refresh generation cannot publish after a newer generation.
- Fingerprints normalize descriptor ordering and include all structural metadata, availability, Shortcut/Evolution identity, and built-in capability metadata.
- Monitoring runs only while at least one authenticated peer exists. Relevant internal notifications trigger a debounced refresh; bounded polling detects external Shortcut/Evolution changes.
- Authentication uses a barrier: the peer becomes broadcast-eligible only after authentication success ordering is established. The peer rechecks the catalog revision after sending authentication success and receives `catalogChanged` if the revision advanced.
- Every `catalogChanged(revision)` corresponds to the revision served by the subsequent snapshot. Failed refresh requests tear down/reconnect or retry with a bounded policy; the dashboard cannot remain permanently gated.

## Security and Resource Bounds

- Transaction messages are encrypted and transcript/session bound.
- Commit, abort, and status operations validate transaction ID, device ID, and provisional session identity.
- Prepared transactions have deadlines and bounded retained-history capacity.
- Catalog requests retain existing frame, icon, descriptor-count, and payload limits.
- No pairing code, credential, proof, decrypted payload, or transaction secret is logged.

## Testing

### Shared protocol

- v1.2 message round trips and stable capability negotiation.
- Transaction IDs and state responses reject mismatches and legacy peers never receive new messages.

### Mac host

- Prepare does not replace an existing credential.
- Commit/abort/status are idempotent; timeout/startup recovery restores prior state.
- Provisional sessions cannot execute actions.
- Real catalog preflight failure prevents commit.
- Two authenticated peers receive one identical catalog revision change.
- Overlapping refreshes cannot publish stale content; debounce, transient failure, rapid stop/start, and teardown are deterministic.
- Authentication revision advancement produces a corresponding invalidation.

### iOS runtime and persistence

- Pair Another failure/cancel/background/dismiss keeps the old session usable.
- Cancel before prepare, after catalog, after envelope write, after commit send, and before reducer adoption has no late publication.
- Lost commit confirmation resolves by transaction-status query.
- Atomic envelope migration, commit, rollback, tombstones, and selected ID survive fault injection at every file-replacement boundary.
- Candidate catalog is actually awaited and validated in production transport.
- Success publishes ordered events and closes the old session only after confirmation.

### App integration

- PairingFeature explicitly finalizes or aborts its prepared transaction.
- Multiple-Mac selection, dashboard status, cached catalog authority, action timeout/retry, first-launch Settings behavior, and foreground lifecycle remain regression-tested.

## Deferred Navigation Refactor

The first-launch Settings implementation remains structurally outside the mutable dashboard stack. It directly displays non-dismissible Settings on first launch and satisfies the user-visible contract. Replacing it with a pushed destination would add state duplication without improving behavior, so it is outside this safety-focused change.
