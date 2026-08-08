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
- `OnlySwitch/` contains the main macOS application, system integrations, Core Data persistence, audio/player functionality, and app-specific UI.
- `OnlyWidget/` contains widget-facing code and must use extension-safe shared models and effects.
- `OnlySwitchRemote/` contains the remote-control application and must share protocol contracts without importing main-app implementation details.
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

