# Task 9 Report — Settings, Mac management, and per-Mac layouts

## Outcome

Implemented Task 9 with a multiple-Mac Settings experience, per-Mac catalog/layout state, retry-safe management, and root coordination.

## TDD evidence

- Initial focused run failed because `MacManagementFeature` and the expanded Settings APIs did not exist.
- The first layout-save queue test exposed an ordering race; a gated regression test then proved that an older successful save could clear a newer rapid-toggle intent. The completion now carries the exact saved layout and starts the newest pending save serially.
- Root selection tests failed before `RemoteAppFeature` handled the new delegate, then passed after root-owned atomic selection persistence and connection selection were added.
- Pair-another layout loading failed before the new Mac’s cached layout was loaded, then passed after pairing success started a tokened per-Mac load.
- Switching back after a failed save failed by restoring stale disk state; it now prefers the latest pending layout so Retry never loses the user’s edits.
- Review-race tests reproduced a pending metadata retry clearing a forget tombstone, stale root metadata reads clobbering newer pair/forget mutations, multi-Mac connected status accumulation, and pair success closing its freshly installed session. Each test failed before the corresponding token/FIFO/root-session fix and passed afterward.

## Implemented behavior

- Clear paired-Mac selector/list with selected, connecting, connected, offline, and pairing-required state plus last-connected metadata.
- Immediate root delegation for Mac selection, with root-owned monotonic app-state persistence and one `RemoteConnectionClient.select` call.
- Generation-tokened layout/catalog loading and selected-Mac filtering for live catalog events.
- Per-Mac single-flight save queues that serialize rapid toggle/move intents, retain the latest intent on failure, and support explicit retry.
- Stable reorder projection over only visible selected descriptors without dropping missing IDs from the full persisted order.
- Built-in, Shortcut, and Evolution sections; unavailable controls remain selectable and show their Mac-provided explanation.
- Pair Another Mac integration and cached-layout loading for the newly paired Mac.
- Mac management view with status/address/date metadata, re-pair action, destructive confirmation, retry-safe forget, deterministic fallback selection, and last-Mac `.allMacsRemoved` delegation.
- Lifecycle cancellation for selected-Mac loads, connection streams, pairing, and presented child effects.
- Dynamic Type, labelled icon buttons, VoiceOver selection/status text, unavailable-reason hints, and localized Settings strings.
- A single tombstoned FIFO mutation domain for forget, pairing commit, revocation, and pending metadata retry. Forget invalidates the per-Mac retry token before its first await; queued retries validate that token and the tombstone immediately before commit.
- Root-owned app-lifetime connection truth with a one-Mac connected set, authenticated snapshot recovery, generation-cancelled metadata refresh, deterministic selection reconciliation, and exact Settings synchronization across dismiss/reopen.
- Pair success adopts the authenticated session installed by `RemoteConnectionRuntime.pair`; the root persists selection/setup state without issuing a redundant `select` that would close and reconnect it.

## Verification

- Focused Settings + MacManagement simulator tests: **15 passed** at the focused checkpoint; final suite contains additional regression cases.
- Focused root + runtime race suite: **52 passed, 0 failed**, including production loopback pairing/session adoption.
- Full `OnlySwitchRemote` iOS 18.6 simulator suite: **107 tests passed, 0 failed** (**115 device/configuration executions** including parameterized cases), confirmed from the xcresult summary.
- `rtk swift test --package-path Modules`: **61 passed, 0 failed** (3 XCTest + 58 Swift Testing).
- Normal `OnlySwitchRemote` simulator build: passed after final UI/localization changes.
- Strict-concurrency build: Swift compilation reached link with no Swift diagnostics, then failed at the known toolchain/package baseline: `ld: framework 'PerceptionCore' not found`.
- `jq empty OnlySwitchRemote/Localizable.xcstrings`: passed.
- `plutil -lint` for `OnlySwitchRemote/Info.plist` and `OnlySwitch.xcodeproj/project.pbxproj`: passed.
- `git diff --check`: passed.
- Security/log scan found no logging of credentials, codes, secrets, or decrypted payloads; only user-facing explanatory text contains the word “credential”.
- Project/build versions and iOS 18.0 deployment settings were preserved.

## Remaining concern

- No physical-device Bonjour/pairing UI walkthrough was performed in this task. Reducer, persistence, connection-event, and simulator integration behavior is covered; live-device visual/network validation remains appropriate during Task 10 integration.
