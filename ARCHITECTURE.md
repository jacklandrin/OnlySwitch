# OnlySwitch Architecture

## Purpose

OnlySwitch is a macOS menu-bar utility that exposes system switches, widgets, an optional desktop pet, an AI assistant, and remote control capabilities. The repository also contains reusable Swift Package modules, a widget target, a remote app, persistence, networking, authentication, and OpenClaw integration.

## Core constraints

1. **Use The Composable Architecture (TCA).** Model user-facing features with state, actions, reducers, and effects using [pointfreeco/swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture). OnlySwitch already uses TCA in multiple package features; extend that pattern consistently.
2. **Use `swift-dependencies` for injection.** Runtime services and external effects should be accessed through `@Dependency` using [pointfreeco/swift-dependencies](https://github.com/pointfreeco/swift-dependencies), rather than being constructed directly inside views or reducers. When introducing or migrating a service, add the dependency at the appropriate module boundary.
3. **Modularize with Swift packages.** Use the `Modules` Swift Package to separate independently buildable and testable functionality. Keep target dependencies intentional and acyclic.
4. **Factor monolithic logic into focused modules.** Extract switch behavior, feature state, persistence, networking, remote protocol, authentication, AI provider integrations, and presentation concerns into focused modules as boundaries become clear.
5. **Keep SwiftUI views free of business logic.** Views render state and send user intent. Business rules, validation, orchestration, permissions, shell/AppleScript effects, and state transitions belong in reducers, domain types, or injected clients.
6. **Follow Swift 6 concurrency safety.** Preserve `Sendable` correctness, actor isolation, structured concurrency, cancellation, and safe crossing of process, networking, persistence, and app/extension boundaries.
7. **Extract common logic for reuse.** Shared models, remote protocol types, switch descriptors, formatting, validation, persistence adapters, and permission policies should have one well-defined implementation and be reused by the app, widget, remote app, and package targets where appropriate.

## Intended dependency direction

```text
App / Widget / Remote app targets
        ↓
Feature modules (TCA reducers, feature state, feature views)
        ↓
Domain modules (switches, remote protocol, models, business rules)
        ↓
Infrastructure modules (system effects, persistence, networking, AI providers, keychain)
```

Infrastructure details must not leak into SwiftUI views. Feature modules should depend on domain abstractions and access infrastructure through injected dependency clients. Shared protocol and model modules must remain safe for all targets that exchange their values.

## Current repository boundaries

- `Modules/` is the primary Swift Package boundary. It contains feature modules such as `OnlyControl`, `OnlyAgent`, `Authenticator`, `StickerView`, and `DesktopPet`, plus shared `Defines`, `Extensions`, `Utilities`, `Networking`, `RemoteCore`, and `RemoteTransport` modules.
- `Modules/Sources/Aphrodite` owns the generated mini-app authoring domain, serialized library, TCA feature, and sandboxed renderer. `SettingsVM.shared` retains the Settings store for the app session so accepted work survives presentation changes, while Aphrodite's injected notification boundary requests permission and reports only persistence-confirmed completion; the app delegate owns foreground banner policy. Authoring prompts, conversation history, model selection, and other authoring configuration never cross the `RemoteCore` or `RemoteTransport` boundary; validated runtime HTML, optional validated SVG, and minimal display metadata may cross that boundary for OnlyRemote. Each app persists only its latest HTML and compact completed user prompts; optimistic replacement prevents a stale edit from restoring a deleted or newer app. Six bundled starter apps are merged into the local library once using stable IDs and a persisted seed version, preserving user edits and deletions. Codex reuses a runtime per model and purpose while mapping each Aphrodite conversation to its own thread. Optional icons come from the same model response as static SVG, are validated before storage and native rendering, and fall back to `star.hexagon` when unavailable. Existing libraries without icons or conversation metadata remain readable. The renderer's only native signals are bounded content-size reports from an isolated WebKit content world; the editor keeps an unscaled logical canvas and scales it to fit its preview, while launchers use the content-height signal. Generated page JavaScript cannot access the handler or any native capability.
- `OnlySwitch/` contains the main macOS application, system integrations, Core Data persistence, audio/player functionality, and app-specific UI. Menu-bar hosts measure active content separately from persistent chrome, then apply the shared `Utilities.AdaptivePanelHeightPolicy` to the hosting screen’s `visibleFrame`. Only Control uses a fixed-size window and keeps overflow scrollable.
- `OnlyWidget/` contains widget-facing code and must use extension-safe shared models and effects.
- `OnlySwitchRemote/` contains the remote-control application and must share protocol contracts without importing main-app implementation details. Its root TCA feature owns the independent Aphrodite personal-tools tab and OnlyRemote Plus sheet. Aphrodite access is gated by verified subscription entitlement, with an embedded paywall for nonmembers. Entitlement refresh is independent of product loading and responds to foregrounding, transaction updates, purchases, restoration, and expiration. A Debug-only Settings submenu provides a persisted paywall bypass for development; Release builds ignore this preference. The injected StoreKit client loads and purchases only the one-month `jacklandrin.onlyremote.plus.monthly` auto-renewable product. Only eligible verified transactions unlock access; pending purchases await a later transaction update, and cancellation does not grant access. Recognized verified transactions are finished after processing, and purchase results update both embedded and Settings paywalls without depending on duplicate transaction notifications.
- `RemoteCore` owns the lightweight, versioned Aphrodite transfer models and the shared HTML and SVG safety validators. Authenticated protocol 1.6 sessions automatically transfer the complete saved library as bounded manifests and 64 KiB chunks with SHA-256 integrity; the wire contract excludes Aphrodite authoring types and private authoring state. OnlyRemote validates each complete transfer before atomically replacing its per-Mac cache, and its WebKit runner uses the same isolated custom origin, content-security policy, and navigation restrictions as the shared sandbox primitives. OnlyRemote lists and runs cached tools but does not create or edit them.
- Launch Campaign uses an injected TCA client to fetch a bounded manifest and dated HTML from the fixed repository origin. A nonpersistent, navigation-restricted WebKit renderer loads while hidden and acknowledges the date only after successful presentation. The page follows app language and native appearance; its OnlyRemote download link opens the existing native QR window. Both windows temporarily rise above menu-bar panels when presented and return to normal level on focus loss, app deactivation, or closing. Failed requests or rendering remain silent and unacknowledged. Debug builds bypass the previously shown date so the latest page appears on every app launch; forced previews do not modify the saved presentation date.
- `OnlySwitchTests/`, `OnlySwitchRemoteTests/`, and `Modules/Tests/` contain unit, integration, feature, protocol, and end-to-end coverage.
- `OpenClaw/skills/onlyswitch-deeplink/` contains the OpenClaw integration documentation and skill for invoking built-in switches through deeplinks.

The project already uses TCA in package features and Swift Package modularization. New work should extend existing reducer/dependency patterns rather than introduce a parallel state-management approach. `swift-dependencies` is an architectural requirement for new injectable services; existing direct constructions may be migrated incrementally at feature boundaries.

## Feature structure guidance

Each feature should aim to contain:

- a `State` value representing renderable state;
- an `Action` enum representing user, lifecycle, and dependency-driven events;
- a reducer that owns transitions and effects;
- a SwiftUI view that observes state and sends actions;
- injected clients for clocks, system commands, permissions, persistence, networking, and AI providers;
- focused tests for business rules, effect behavior, authorization failures, and important edge cases.

## System and remote boundaries

Changes to switches, shell commands, AppleScript, keychain data, Core Data, widgets, remote sessions, or deeplinks must account for:

- macOS authorization and user-cancelled permission flows;
- command failure, unavailable hardware, unsupported OS versions, and missing executables;
- secure storage and migration of credentials, pairing data, and provider keys;
- remote pairing, authentication, encryption, framing, ordering, replay protection, cancellation, and reconnect behavior;
- widget refresh limits and stale state;
- process isolation and extension-safe serialization;
- localization, accessibility, and menu-bar interaction behavior.

## Testing expectations

Prefer deterministic reducer and domain tests with controlled dependencies. Add integration coverage for Core Data, system-effect adapters, remote transport, pairing, and cross-target behavior when reducer tests cannot prove correctness. New concurrency-sensitive code should include tests for cancellation, ordering, actor isolation assumptions, malformed frames, connection loss, and failure propagation where applicable.


## Xcode Cleaner

`Modules/Sources/XcodeCleaner` owns the macOS Settings cleaner, its TCA state and views, and an injected `XcodeCleanerClient`. SettingsVM retains the store for the app session. No cleanup API is exposed to widgets, OnlyRemote, or deeplinks. Inventory and cleanup authorization remain in memory.

Filesystem inventory is restricted to the current user's standard DerivedData, Xcode cache, SwiftPM cache/download, CoreSimulator cache/log, and Xcode DeviceSupport directories. DerivedData includes its nested Build, Index, ModuleCache, and SourcePackages artifacts exactly once. Archives, source repositories, Xcode.app, SDKs, credentials, and custom project build directories are excluded. Cleanup preserves category roots, rejects symbolic-link ancestors and changed root identities, and reports individual failures. There is no privilege escalation. Sizes use allocated file bytes and represent unknown or partial inventories explicitly.

Simulator devices and runtime images are inventoried through an injected argument-array `simctl` command boundary. Device/runtime and DeviceSupport deletion require item-specific confirmation. Device deletion requires a fresh shutdown inventory; runtime deletion requires the runtime-image UUID, removable metadata, and no booted device using it. Raw simulator/runtime directory deletion is forbidden. The owned command process has bounded captured output, a timeout, and cancellation; scanning and file operations run outside the main actor. Focused temporary-fixture and reducer tests never clean live developer data.

The Xcode Cleaner built-in switch controls only `showXcodeCleanerTabKey`, defaulting to true, and the Settings visibility toggle uses the same exportable preference. One-time discovery has its own nonexportable marker. The cleaner is local-only: widget entity discovery, remote catalogs/status and forged remote action routing exclude it. The previous Xcode DerivedData cleanup action keeps its existing identity and behavior.

Settings, OnlySwitch's menu-bar list, and OnlyControl share `SettingsVM.shared.xcodeCleanerStore` and its current snapshot authorization. Panel hosts own scrolling and request a compact presentation where appropriate. Host IDs keep confirmation dialogs with their initiating host and cancel an in-progress scan only after its last visible host disappears; ongoing cleanup survives host disappearance. Explicit simulator runtime identifiers and optional descriptor names drive deterministic OS/version groups, independent of generic display details or deletion IDs.

The cleaner supports session-only multi-selection and freezes each confirmed batch as an ordered item list with its original snapshot and host-owned confirmation token. Filesystem and simulator adapters retain bounded immutable authorization contexts, independently pinning the displayed context and in-flight cleanup. The coordinator gates destructive batches across suspension points, partitions each batch once per adapter, and invalidates inventory candidates that cross a cleanup revision. Only accepted inventories activate display authorization; newer background candidates never rewrite earlier root identities or simulator targets.

Confirmed successful rows leave the displayed inventory immediately; per-item failures remain selectable and partially removed categories have unknown remaining bytes. Remaining totals are explicitly estimates until a complete accepted background remeasurement. Refresh uses its own generation and inventory revision, so it neither blocks the next cleanup nor resurrects rows after a newer mutation. Empty successfully cleaned cache roots stay suppressed during automatic refresh while regenerated nonempty content can return; an explicit scan shows the complete inventory. Simulator cleanup shares one command-only fresh preflight for the batch and does not repeat device-directory size enumeration. Actual disk-space recovery is never inferred by subtracting stale inventory totals.

## App Uninstaller

`Modules/Sources/AppUninstaller` owns the macOS-only uninstaller domain, TCA feature, native presentation and injected `AppUninstallerClient`. `SettingsVM.shared.appUninstallerStore` retains session state across Settings, the menu-bar list and OnlyControl. The feature accepts one local application bundle through a file drop or native chooser; selection and confirmation remain reducer-owned. Host-specific confirmation tokens freeze the accepted inventory and ordered selection. A disappearing host dismisses its pending confirmation, scanning is cancelled after the last visible host leaves, and an already confirmed removal continues independently of presentation.

Inventory includes the chosen `.app` and only exact bundle-identifier matches in the current user's `Library/Preferences/<identifier>.plist`, `Library/Caches/<identifier>`, `Library/Application Support/<identifier>`, `Library/Saved Application State/<identifier>.savedState`, `Library/Logs/<identifier>` and `Library/Containers/<identifier>`. ByHost preferences additionally require the exact `<identifier>.<UUID>.plist` filename structure. The feature does not guess by app name, enumerate arbitrary home locations, remove shared group containers, or manage keychains, launch agents, receipts or system Library files. Full Disk Access can expose additional matches within this allowlist; it does not expand the discovery policy. Inaccessible files and unknown sizes are explicit, so an accepted inventory is not a claim that all related app data has been discovered.

The filesystem actor keeps bounded immutable scan authorizations in memory and pins the displayed context. Removal accepts snapshot and item identifiers, never arbitrary caller-provided paths. Before each item it rechecks app metadata, running-app state, file and ancestor identities, and the protected-location/self-app policy. User-controlled symbolic links and symbolic-link ancestors are rejected; only the known root-owned macOS `/var`, `/tmp` and `/etc` aliases are permitted and identity-pinned. System/Apple apps, apps nested inside another app, OnlySwitch itself, running apps and bundles on excluded system/network/volume paths are not eligible. Associated files are processed before the application bundle, and successful item authorizations are consumed to prevent replay. A single removal batch is admitted at a time, with individual outcomes retained for failed items. If a selected associated file fails, other selected data files continue but the application bundle remains available for a safe retry.

Every removal requires an explicit review and confirmation of selected files, and uses `FileManager.trashItem` through an injected effect. There is no privilege escalation, permanent deletion, shell deletion, automatic app termination or restart. Filesystem work runs outside the main actor; the chooser, running-app lookup and privacy-settings navigation use explicit main-actor boundaries. Identity revalidation reduces accidental or stale-path removal, but path-based Trash operations cannot provide an atomic guarantee against a hostile same-user process substituting a path between the final check and the move.

The App Uninstaller built-in switch controls only the exportable `showAppUninstallerTabKey` preference, defaulting to true. A separate nonexportable discovery marker adds the switch once without overriding later user customization. Hiding the selected list/OnlyControl tab returns to controls; Settings remains an entry point. The uninstaller is local-only: widget discovery, remote catalogs/status and forged remote action routing exclude it, and no destructive deeplink is exposed. Focused fixture and reducer tests use temporary app/Library trees and an injected Trash recorder; verification never uninstalls a real user application.

The list and OnlyControl suppress outside-click dismissal while their own App Uninstaller section is selected, allowing Finder selection and dragging; explicit close and status-item toggling remain available.


## Tailscale

`Modules/Sources/Tailscale` owns the macOS-only TCA account/settings feature, Sendable models, injected `TailscaleClient`, and official-client command adapter. `SettingsVM.shared.tailscaleStore` retains its session state. The menu-bar connection provider uses the same live client coordinator; it controls connection state rather than the visibility of a secondary tab. Its stable built-in identifier is `281_474_976_710_656`; the historical visibility bitmask remains frozen and one-time discovery does not override later user customization.

OnlySwitch requires an installed, working Tailscale client. Browser authorization adds saved accounts through the official CLI; Tailscale owns the VPN configuration, system permission prompts and credentials. Only one account is active at a time. OnlySwitch does not persist passwords, authorization URLs, API keys or account tokens. It exposes supported network preferences and directs app-specific startup, Dock, notification, VPN On Demand and Tailnet Lock management to the official client.

The command boundary uses fixed executable discovery and argument arrays, bounded output, timeout and cancellation of the owned process. A shared coordinator gates mutations across Settings and the menu-bar switch; reducer refresh generations and adapter read generations prevent stale results from replacing newer state. Settings account-sensitive intents carry the displayed active account’s stable ID, which the coordinator checks during preflight and immediately before writing. An externally changed active account rejects the operation and triggers a refresh. The official CLI cannot supply an atomic cross-process account target, so a simultaneous external account switch after the final check remains a limitation. Views only render confirmed snapshots and send actions. Failed connection changes restore the last confirmed display and offer the Tailscale Settings entry point, including keyboard and OnlyControl activation paths.

The feature is local-only: widget discovery, remote catalogs, status lookups and forged remote command routing exclude Tailscale. Account identities and browser authorization never enter the remote protocol or widget payloads. Verification uses injected clients and temporary process fixtures and never changes the developer's actual VPN connection or account.

Executable discovery accepts the native app CLI (including supported executable-name variants) or a native Homebrew binary. Shell launchers without `exec` are not executed. The command deadline covers pipe draining as well as process execution, and termination validates and targets the owned process group so inherited pipes cannot leave an unbounded wait. Cancelling authorization waits for the coordinator’s owned CLI to finish before refreshing the resulting client state.
