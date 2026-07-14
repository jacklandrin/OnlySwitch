# OnlySwitch iOS Remote Control Design

## Summary

Add a separate `OnlySwitch Remote` iOS/iPadOS application target to the existing `OnlySwitch.xcodeproj`. The remote discovers and pairs with multiple Macs on the local network, displays a per-Mac tile dashboard, and invokes the Mac app's built-in controls, installed Shortcuts, and installed Evolutions.

The Mac remains the only process that executes commands. The iOS app receives portable control descriptions and status, sends authenticated typed actions, and never contains macOS command implementations.

## Product Requirements

- Support iOS and iPadOS 18 or later.
- Use Swift 6.2, SwiftUI, and The Composable Architecture 1.25.3.
- Add the iOS app as a separate target in the existing Xcode project and repository.
- Support pairing and retaining multiple Macs, with a selector on the dashboard.
- Discover Macs with Bonjour on the local network.
- Require a one-time pairing code and retain per-device credentials in Keychain.
- Fetch every built-in control supported by the Mac, every Shortcut installed in macOS Shortcuts, and every locally installed Evolution.
- Show unavailable built-ins disabled with an explanation instead of hiding them.
- Store selected tiles and tile order independently for each paired Mac.
- Show current state and secondary information for selected controls.
- Require confirmation before sending destructive actions.
- Use a tile-first dashboard without a tab bar.
- Put a hamburger button in the dashboard's top-right corner; tapping it pushes Settings.
- On the first launch, open Settings so the user can pair a Mac and choose tiles. Later launches open the dashboard when at least one paired Mac exists. If all Macs are forgotten, return to Settings.

## Scope and Non-Goals

Version 1 controls Macs only while the iOS app is in the foreground and both devices can communicate over the local network. It does not use iCloud, a relay server, push notifications, remote access outside the LAN, widgets, Siri/App Intents, or background command execution.

The app triggers existing switch, player, button, Shortcut, and Evolution behaviors. It does not reproduce the Mac's detailed player controls, Authenticator interface, AI Commander interface, or feature-specific settings on iOS. These controls can expose their existing primary toggle or trigger behavior when remotely available.

## Repository and Target Structure

The existing Xcode project gains an `OnlySwitchRemote` iOS application target and an `OnlySwitchRemoteTests` test target. The existing `Modules` package gains two focused cross-platform products:

- `RemoteCore`: platform-neutral Codable protocol messages, control descriptors, identifiers, action and error types, protocol versioning, and framing limits.
- `RemoteTransport`: Network.framework connection abstractions, message framing, pairing/session cryptography, and testable clock/randomness dependencies. It depends on `RemoteCore` and Apple frameworks only.

Existing macOS-only `Switches` and UI modules remain macOS-only. Neither shared remote module imports AppKit or references `SwitchProvider`.

The Mac target adds a catalog adapter and command router that bridge shared remote types to the existing implementations. The iOS target depends only on the shared remote products, TCA, and Apple platform frameworks.

## System Architecture

### Mac application

The Mac app owns four new units:

1. `RemoteAccessSettingsFeature` and its SwiftUI view expose service configuration and pairing management.
2. `RemoteHost` is an actor that owns the Bonjour listener and active authenticated sessions.
3. `RemoteCatalogProvider` converts existing controls into portable descriptors and status snapshots.
4. `RemoteCommandRouter` validates an action and invokes the corresponding existing built-in, Shortcut, or Evolution implementation.

The settings feature starts or stops `RemoteHost`; app lifecycle code does not implement network or pairing details. The router is the only remote layer allowed to invoke existing command implementations.

### iOS application

The iOS app is composed of independent TCA features:

- `RemoteAppFeature`: application lifecycle, selected Mac, first-launch routing, and navigation stack. The dashboard is the stack root; setup Settings is pushed without a back action until at least one Mac is paired.
- `DashboardFeature`: selected tiles, subscription state, command progress, destructive confirmation, and action results.
- `SettingsFeature`: current Mac, paired Mac list, per-Mac tile selection, and tile ordering.
- `PairingFeature`: discovery, code entry, pairing progress, validation, and credential persistence.
- `MacManagementFeature`: selecting, reconnecting, and forgetting a paired Mac.

Side effects are exposed as TCA dependencies:

- `RemoteConnectionClient` wraps Bonjour discovery and authenticated session actors.
- `RemotePersistenceClient` stores the selected Mac, first-launch completion, and per-Mac layouts.
- `RemoteKeychainClient` stores credentials and never exposes them to view state.

Each paired Mac has a stable installation UUID. That UUID keys its saved dashboard layout even if the Mac's display name changes.

## Mac Remote Access Settings

Add an `iOS Remote` item to the existing Mac Settings sidebar. It contains:

- `Enable Remote Access`, disabled by default.
- An editable Bonjour display name, initially derived from the Mac name.
- Listener status and the number of connected devices.
- A `Start Pairing` action that shows the current expiring code and remaining validity.
- A paired-device list containing the device name and last-connected date.
- An individual `Revoke` action for each device.

Disabling remote access stops advertising, closes sessions, and preserves paired-device credentials. Revoking a device deletes only that credential and closes that device's sessions. Starting a new pairing window invalidates any previous unused code.

## Discovery, Pairing, and Session Security

The Mac advertises a Bonjour service containing only its display name, stable installation UUID, and protocol major version. Control catalogs and device information are unavailable before authentication.

Pairing uses a random, human-readable 12-character code with ambiguous characters removed. The code is valid for five minutes and is never sent directly over the connection. The client and Mac exchange ephemeral P-256 public keys, derive a shared secret, and use HKDF-SHA256 with the pairing code and handshake transcript to derive a pairing key. Each side proves possession of the derived key before the Mac issues a random 256-bit device credential.

Five failed proofs invalidate the pairing window. The Mac accepts only one successful device enrollment from a pairing code. Both sides store the device credential in Keychain, together with the stable Mac/device identifiers needed to locate it.

Later sessions use fresh ephemeral P-256 key agreement plus the stored credential to authenticate the transcript and derive directional encryption keys. All post-handshake frames use AES-GCM. A session-specific nonce prefix and monotonically increasing counter prevent nonce reuse and reject replayed frames. Long-lived credentials never travel over the network.

Each frame has a fixed header containing protocol version, message type, payload length, and request or sequence identifier. Receivers reject unsupported major versions, invalid authentication, non-monotonic counters, and frames larger than 4 MiB before decoding payloads. Icon payloads are limited to 256 KiB each.

The iOS app reconnects while foregrounded using bounded exponential backoff. Bonjour appearance, app activation, changing the selected Mac, or an explicit retry triggers an immediate attempt. Moving to the background closes active sessions. Forgetting a Mac deletes its credential, cached catalog, and saved layout.

## Protocol

Every message envelope includes a protocol version. Initial version 1 messages are:

- `clientHello` / `serverHello`
- `pairingRequest` / `pairingProof` / `pairingResult`
- `authenticationProof` / `authenticationResult`
- `catalogRequest` / `catalogSnapshot` / `catalogChanged`
- `subscriptionUpdate` / `statusSnapshot` / `statusChanged`
- `actionRequest` / `actionResult`
- `ping` / `pong`
- `sessionError`

Minor protocol additions must remain backward-compatible. A major-version mismatch produces an upgrade-required error and does not authenticate the session.

## Control Model and Catalog

`RemoteControlID` contains a `kind` and stable string value:

- Built-in: `.builtIn` plus the existing `SwitchType.rawValue` encoded as a decimal string.
- Shortcut: `.shortcut` plus the exact installed Shortcut name because macOS does not expose a stable Shortcut UUID. Renaming a Shortcut therefore creates a new remote identity and removes the old one.
- Evolution: `.evolution` plus the existing Evolution UUID string.

A `RemoteControlDescriptor` contains:

- ID and kind.
- Display title.
- Behavior: `switch`, `button`, or `player`.
- Portable icon: an SF Symbol name when possible, otherwise a 60-by-60 PNG.
- Availability and a user-facing unavailable reason.
- Whether the action is destructive.
- Whether persistent Boolean status and secondary information are supported.

The Mac catalog includes all `SwitchType.allCases`. `isVisible()` contributes to availability but is not the only source; a dedicated availability adapter supplies useful reasons for missing hardware, permissions, configuration, or operating-system support.

The Shortcut catalog comes from the same `shortcuts list` command already used by `ShortcutsSettingVM`, without filtering by the Mac menu toggle. The Evolution catalog comes from all locally stored Evolution entities, without filtering by the active menu ID list.

Catalog changes are pushed after Shortcuts, Evolutions, availability, or built-in metadata changes. If a selected control disappears, its ID remains in the saved layout but the dashboard omits it; Settings can remove the missing selection. If it reappears with the same ID, it returns to the prior layout position.

## Status and Subscription Flow

The catalog describes every control but does not continuously poll every control. The iOS app sends the selected control IDs for the active Mac in `subscriptionUpdate`.

The Mac immediately returns status for subscribed controls and refreshes them while at least one client subscribes. It also pushes status after a local OnlySwitch action, a remote action, and existing change notifications. The refresh scheduler coalesces duplicate subscriptions across clients and avoids overlapping status calls for the same ID.

`RemoteControlStatus` contains availability, optional Boolean state, optional secondary information, processing state, revision, and update date. Buttons have no persistent Boolean state. Switches and players may have Boolean state. Secondary information reuses the existing provider output after conversion to a concise display string.

When disconnected, the iOS app retains the last catalog and per-Mac layout, marks all status stale, displays an offline indicator, and disables every command action.

## Action Semantics

`RemoteActionRequest` contains a unique request UUID, control ID, and one typed action:

- `setState(Bool)` for switch/player controls.
- `trigger` for buttons, Shortcuts, and button-style Evolutions.

The Mac validates the authenticated device, control existence, current availability, and action compatibility before execution. It maintains a bounded cache of recent request UUIDs and their results for the life of the host process so a retransmitted request cannot execute twice.

The iOS dashboard does not update status optimistically. A tile shows progress while awaiting `actionResult`. On success, the Mac sends the authoritative result and broadcasts a fresh status revision. On failure or timeout, the tile returns to its prior state and shows a concise error.

Destructive metadata causes the iOS app to present a confirmation dialog naming the Mac and control. Confirmation is an iOS safety affordance; the Mac still performs full validation.

## iOS User Interface

### Dashboard

The dashboard is the normal root screen after setup. It contains:

- A centered selected-Mac picker near the top.
- A hamburger button in the top-right toolbar position.
- An adaptive grid of the selected Mac's tiles: two columns on compact iPhone widths and additional columns as iPad width permits.
- A connection or stale-state indicator when the selected Mac is unavailable.

Each tile shows its icon, title, secondary information, state, availability, and in-flight progress. Disabled controls remain visible with their explanation. Tiles use accessible buttons, Dynamic Type, VoiceOver labels that include Mac/title/state, sufficient contrast, and motion that honors Reduce Motion.

Tapping the hamburger pushes Settings on the navigation stack. There is no tab bar. Standard back navigation returns to the dashboard.

### Settings

On a fresh install, the app immediately presents Settings above the dashboard root and hides back navigation until a Mac is paired. It contains:

- Selected and paired Macs, including connection state.
- `Pair Another Mac`, leading to discovery and code entry.
- Device management and forgetting.
- A per-selected-Mac catalog grouped into Built-ins, Shortcuts, and Evolutions.
- Tile inclusion toggles, including disabled unavailable controls with explanations.
- An edit mode for ordering selected tiles.

Completing the first pairing and initial selection marks first-launch setup complete and pops Settings to reveal the dashboard. When Settings is opened later from the hamburger button, standard back navigation returns to the dashboard. Later launches open the dashboard when a pairing exists. Removing the last pairing pushes the non-dismissible setup Settings route again.

## Persistence

Keychain stores Mac/device credentials and cryptographic material. Ordinary app storage stores:

- Selected Mac installation UUID.
- First-launch setup completion.
- Cached display metadata for paired Macs.
- Per-Mac ordered arrays of selected `RemoteControlID` values.
- Last catalog and status snapshot for offline display, stored as files in Application Support rather than UserDefaults.

Credential revocation and forgetting are distinct. Revocation on the Mac rejects the next iOS authentication and directs the app to Settings. Forgetting on iOS removes all local data for that Mac. Disabling remote access on the Mac does neither.

## Error Handling

- Discovery with no results shows setup guidance and a retry action.
- Invalid, expired, or rate-limited pairing codes remain on code entry with a specific recoverable message.
- Authentication revocation marks the Mac as requiring pairing and routes to Settings.
- Protocol mismatch shows the required app side to upgrade.
- Connection loss preserves cached layout and status but disables actions.
- Catalog decoding, oversized frames, replay, or authentication failures close the session without executing an action.
- Action validation and execution failures use structured error codes plus a user-safe message.
- Network and status tasks are cancelled when their feature is dismissed, the Mac selection changes, or the app backgrounds.

## Testing and Verification

`RemoteCore` and `RemoteTransport` tests cover Codable compatibility, partial and combined frames, size limits, key derivation, proof validation, AES-GCM round trips, nonce/counter enforcement, replay rejection, and credential redaction.

Mac tests use fake control providers to cover complete catalog generation, unavailable reasons, installed Shortcut and Evolution enumeration, action compatibility, destructive metadata, request deduplication, and authoritative status broadcast.

iOS TCA `TestStore` tests cover first-launch Settings routing, pairing success and failure, selecting and forgetting Macs, per-Mac independent layouts, Mac switching, subscription updates, reconnecting, destructive confirmation, successful actions, timeouts, failures, stale state, and revocation.

A loopback integration test connects a test Network.framework listener and client through pairing, authentication, catalog exchange, subscription, and one idempotent action. UI verification covers compact and regular widths, Dynamic Type, VoiceOver labels, dark appearance, and Reduce Motion.

Completion requires:

- Passing `swift test` for package modules.
- A successful macOS build and existing test suite.
- A successful iOS Simulator build and the new iOS test suite on an iOS 18-or-newer simulator.
- No credential, pairing code, or decrypted payload logging in release builds.

## Delivery Boundaries

Implementation should proceed in independently testable slices: shared protocol and transport, Mac catalog/router, Mac host and settings, iOS connection/persistence, pairing and Mac management, dashboard, settings/layout editing, then integration and accessibility verification. Existing unrelated code and the current uncommitted Xcode project version bump must be preserved.
