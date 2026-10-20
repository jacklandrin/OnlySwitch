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

