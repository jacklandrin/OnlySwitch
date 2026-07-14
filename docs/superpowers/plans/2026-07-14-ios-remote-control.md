# OnlySwitch iOS Remote Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a separate SwiftUI/TCA iOS and iPadOS app that securely discovers, pairs with, monitors, and controls multiple OnlySwitch Macs on the local network.

**Architecture:** Add platform-neutral `RemoteCore` and `RemoteTransport` Swift package products, bridge them to existing Mac controls through a catalog/router/host boundary, and build an `OnlySwitchRemote` iOS target from focused TCA features. Bonjour and Network.framework provide discovery and transport; CryptoKit and Keychain provide authenticated encrypted sessions; the Mac remains the only command executor.

**Tech Stack:** Swift 6.2, SwiftUI, The Composable Architecture 1.25.3, Network.framework, CryptoKit, Security/Keychain, Swift Testing, XCTest, Xcode 26.6.

## Global Constraints

- Support iOS and iPadOS 18 or later and preserve macOS 14 support.
- Add `OnlySwitchRemote` and `OnlySwitchRemoteTests` to the existing `OnlySwitch.xcodeproj`; do not create another project.
- Use the existing exact TCA version 1.25.3 and add no third-party dependencies.
- Keep macOS command execution in the Mac target; shared modules must not import AppKit or reference `SwitchProvider`.
- Remote access is disabled by default and never exposes a catalog before authentication.
- Persist credentials only in Keychain; never log pairing codes, credentials, session keys, or decrypted payloads.
- Preserve the user's existing uncommitted `CURRENT_PROJECT_VERSION = 260` changes in `OnlySwitch.xcodeproj/project.pbxproj`.
- Use `rtk` for every shell command.
- Use `/tmp/OnlySwitchDerivedData` and `/tmp/OnlySwitchRemoteDerivedData` for Xcode verification output.

## File Structure

### Shared package

- `Modules/Sources/RemoteCore/`: wire-safe protocol version, identifiers, descriptors, status, actions, errors, and messages.
- `Modules/Sources/RemoteTransport/`: length-prefix framing, pairing-code generation, session key derivation, authenticated encryption, and connection event abstractions.
- `Modules/Tests/ModulesTests/RemoteCoreTests.swift`: model round-trip and compatibility tests.
- `Modules/Tests/ModulesTests/RemoteFrameCodecTests.swift`: partial/combined/oversized frame tests.
- `Modules/Tests/ModulesTests/RemoteSessionCryptoTests.swift`: key agreement, proof, encryption, nonce, and replay tests.

### Mac target

- `OnlySwitch/Features/RemoteAccess/Catalog/`: bridge existing built-ins, Shortcuts, and Evolutions to shared descriptors/status.
- `OnlySwitch/Features/RemoteAccess/Commands/`: typed action validation, routing, result deduplication.
- `OnlySwitch/Features/RemoteAccess/Host/`: listener, peer session, credentials, subscriptions, refresh scheduling.
- `OnlySwitch/Features/RemoteAccess/Settings/`: TCA settings feature and SwiftUI settings page.
- `OnlySwitchTests/RemoteAccess/`: catalog, router, credential, and host integration tests.

### iOS target

- `OnlySwitchRemote/App/`: app entry, root feature, and navigation.
- `OnlySwitchRemote/Models/`: paired Mac and per-Mac layout persistence models.
- `OnlySwitchRemote/Dependencies/`: connection, persistence, and Keychain TCA clients.
- `OnlySwitchRemote/Features/Pairing/`: discovery and one-time pairing.
- `OnlySwitchRemote/Features/Settings/`: paired Macs, selection, forgetting, tile inclusion/order.
- `OnlySwitchRemote/Features/Dashboard/`: Mac picker, adaptive tile grid, status, confirmations, actions.
- `OnlySwitchRemoteTests/`: TCA, persistence, and connection integration tests.

---

### Task 1: Shared RemoteCore protocol

**Files:**
- Modify: `Modules/Package.swift`
- Create: `Modules/Sources/RemoteCore/RemoteProtocolVersion.swift`
- Create: `Modules/Sources/RemoteCore/RemoteControlID.swift`
- Create: `Modules/Sources/RemoteCore/RemoteControlDescriptor.swift`
- Create: `Modules/Sources/RemoteCore/RemoteControlStatus.swift`
- Create: `Modules/Sources/RemoteCore/RemoteAction.swift`
- Create: `Modules/Sources/RemoteCore/RemoteProtocolError.swift`
- Create: `Modules/Sources/RemoteCore/RemoteMessage.swift`
- Create: `Modules/Tests/ModulesTests/RemoteCoreTests.swift`

**Interfaces:**
- Produces: `RemoteProtocolVersion.current`, `RemoteControlID`, `RemoteControlDescriptor`, `RemoteControlStatus`, `RemoteActionRequest`, `RemoteActionResult`, `RemoteMessage`.
- Consumes: Foundation only.

- [ ] **Step 1: Add failing Codable and identity tests**

```swift
import Foundation
import Testing
@testable import RemoteCore

struct RemoteCoreTests {
    @Test func controlIDRoundTrips() throws {
        let value = RemoteControlID(kind: .evolution, value: UUID().uuidString)
        #expect(try JSONDecoder().decode(RemoteControlID.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func actionMessageRoundTrips() throws {
        let request = RemoteActionRequest(
            requestID: UUID(),
            controlID: .init(kind: .builtIn, value: "2"),
            action: .setState(true)
        )
        let message = RemoteMessage.actionRequest(request)
        #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func majorCompatibilityRejectsDifferentMajor() {
        #expect(!RemoteProtocolVersion.current.isCompatible(with: .init(major: 2, minor: 0)))
        #expect(RemoteProtocolVersion.current.isCompatible(with: .init(major: 1, minor: 7)))
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails because `RemoteCore` does not exist**

Run: `rtk swift test --package-path Modules --filter RemoteCoreTests`

Expected: FAIL with `no such module 'RemoteCore'`.

- [ ] **Step 3: Add the package product and target**

Add `.iOS(.v18)` beside `.macOS(.v14)`, add a `RemoteCore` library product, add a dependency-free `RemoteCore` target, and add `RemoteCore` to `ModulesTests` dependencies:

```swift
.library(name: "RemoteCore", targets: ["RemoteCore"])

.target(name: "RemoteCore")
```

- [ ] **Step 4: Implement the complete wire model**

Use these exact public signatures, one primary type per file:

```swift
public struct RemoteProtocolVersion: Codable, Equatable, Sendable {
    public static let current = Self(major: 1, minor: 0)
    public let major: UInt16
    public let minor: UInt16
    public func isCompatible(with other: Self) -> Bool { major == other.major }
}

public struct RemoteControlID: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case builtIn, shortcut, evolution }
    public let kind: Kind
    public let value: String
}

public struct RemoteControlDescriptor: Codable, Equatable, Identifiable, Sendable {
    public enum Behavior: String, Codable, Sendable { case `switch`, button, player }
    public enum Icon: Codable, Equatable, Sendable { case systemSymbol(String); case png(Data) }
    public let id: RemoteControlID
    public let title: String
    public let behavior: Behavior
    public let icon: Icon
    public let isAvailable: Bool
    public let unavailableReason: String?
    public let isDestructive: Bool
    public let supportsStatus: Bool
    public let supportsSecondaryInformation: Bool
}

public struct RemoteControlStatus: Codable, Equatable, Identifiable, Sendable {
    public let id: RemoteControlID
    public let isAvailable: Bool
    public let unavailableReason: String?
    public let isOn: Bool?
    public let secondaryInformation: String?
    public let isProcessing: Bool
    public let revision: UInt64
    public let updatedAt: Date
}

public enum RemoteControlAction: Codable, Equatable, Sendable { case setState(Bool); case trigger }
public struct RemoteActionRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let controlID: RemoteControlID
    public let action: RemoteControlAction
}
public struct RemoteActionResult: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let result: Result<RemoteControlStatus?, RemoteProtocolError>
}

public struct RemoteProtocolError: Codable, Error, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case upgradeRequired, authenticationFailed, pairingExpired, pairingRateLimited
        case controlNotFound, controlUnavailable, actionNotSupported, executionFailed
        case requestTimedOut, invalidFrame, replayDetected
    }
    public let code: Code
    public let message: String
}
```

Implement custom Codable for associated-value enums and `RemoteActionResult.result` so case names are explicit and stable. Define `RemoteProtocolError` as a Codable, Equatable error with codes `upgradeRequired`, `authenticationFailed`, `pairingExpired`, `pairingRateLimited`, `controlNotFound`, `controlUnavailable`, `actionNotSupported`, `executionFailed`, `requestTimedOut`, `invalidFrame`, and `replayDetected`, plus a user-safe message.

Use these exact message payloads:

```swift
public struct ClientHello: Codable, Equatable, Sendable { public let version: RemoteProtocolVersion; public let deviceID: UUID; public let deviceName: String; public let ephemeralPublicKey: Data }
public struct ServerHello: Codable, Equatable, Sendable { public let version: RemoteProtocolVersion; public let macID: UUID; public let macName: String; public let ephemeralPublicKey: Data; public let challenge: Data }
public struct PairingProof: Codable, Equatable, Sendable { public let deviceID: UUID; public let proof: Data }
public struct PairingSuccess: Codable, Equatable, Sendable { public let macID: UUID; public let credential: Data }
public struct AuthenticationProof: Codable, Equatable, Sendable { public let deviceID: UUID; public let proof: Data }
public struct AuthenticationSuccess: Codable, Equatable, Sendable { public let sessionID: UUID; public let catalogRevision: UInt64 }

public enum RemoteMessage: Codable, Equatable, Sendable {
    case clientHello(ClientHello)
    case serverHello(ServerHello)
    case pairingRequest
    case pairingProof(PairingProof)
    case pairingResult(Result<PairingSuccess, RemoteProtocolError>)
    case authenticationProof(AuthenticationProof)
    case authenticationResult(Result<AuthenticationSuccess, RemoteProtocolError>)
    case catalogRequest
    case catalogSnapshot(revision: UInt64, controls: [RemoteControlDescriptor])
    case catalogChanged(revision: UInt64)
    case subscriptionUpdate(Set<RemoteControlID>)
    case statusSnapshot([RemoteControlStatus])
    case statusChanged(RemoteControlStatus)
    case actionRequest(RemoteActionRequest)
    case actionResult(RemoteActionResult)
    case ping(UInt64)
    case pong(UInt64)
    case sessionError(RemoteProtocolError)
}
```

Custom Codable for `Result`-carrying cases must encode either `success` or `failure`, never both. Credential bytes appear only in the encrypted `pairingResult` payload after mutual proof succeeds.

- [ ] **Step 5: Run RemoteCore tests**

Run: `rtk swift test --package-path Modules --filter RemoteCoreTests`

Expected: PASS.

- [ ] **Step 6: Commit the protocol model**

```bash
rtk git add Modules/Package.swift Modules/Sources/RemoteCore Modules/Tests/ModulesTests/RemoteCoreTests.swift
rtk git commit -m "feat: add remote control protocol models"
```

### Task 2: Secure framing and session cryptography

**Files:**
- Modify: `Modules/Package.swift`
- Create: `Modules/Sources/RemoteTransport/RemoteFrameCodec.swift`
- Create: `Modules/Sources/RemoteTransport/PairingCode.swift`
- Create: `Modules/Sources/RemoteTransport/RemoteSessionCrypto.swift`
- Create: `Modules/Tests/ModulesTests/RemoteFrameCodecTests.swift`
- Create: `Modules/Tests/ModulesTests/RemoteSessionCryptoTests.swift`

**Interfaces:**
- Consumes: `RemoteMessage`, `RemoteProtocolError` from `RemoteCore`.
- Produces: `RemoteFrameCodec.append(_:)`, `RemoteFrameCodec.encode(_:)`, `PairingCode.generate(using:)`, `RemoteSessionCrypto.makePairingProof`, `deriveSessionKeys`, `seal`, and `open`.

- [ ] **Step 1: Add failing frame-boundary tests**

```swift
import Foundation
import Testing
@testable import RemoteCore
@testable import RemoteTransport

struct RemoteFrameCodecTests {
    @Test func partialFrameWaitsForRemainder() throws {
        var codec = RemoteFrameCodec(maximumPayloadSize: 4 * 1_024 * 1_024)
        let frame = try codec.encode(.ping(42))
        #expect(try codec.append(frame.prefix(3)).isEmpty)
        #expect(try codec.append(frame.dropFirst(3)) == [.ping(42)])
    }

    @Test func combinedFramesDecodeInOrder() throws {
        var codec = RemoteFrameCodec(maximumPayloadSize: 4 * 1_024 * 1_024)
        let data = try codec.encode(.ping(1)) + codec.encode(.pong(2))
        #expect(try codec.append(data) == [.ping(1), .pong(2)])
    }

    @Test func oversizedFrameIsRejectedBeforePayloadDecode() throws {
        var codec = RemoteFrameCodec(maximumPayloadSize: 8)
        #expect(throws: RemoteProtocolError.self) { try codec.append(Data([0, 0, 0, 9])) }
    }
}
```

- [ ] **Step 2: Add failing deterministic cryptography tests**

```swift
@Test func bothPeersDeriveMatchingDirectionalKeys() throws {
    let client = P256.KeyAgreement.PrivateKey()
    let server = P256.KeyAgreement.PrivateKey()
    let credential = Data(repeating: 7, count: 32)
    let clientKeys = try RemoteSessionCrypto.deriveSessionKeys(
        role: .client, privateKey: client, peerPublicKey: server.publicKey.rawRepresentation,
        credential: credential, transcript: Data("hello".utf8)
    )
    let serverKeys = try RemoteSessionCrypto.deriveSessionKeys(
        role: .server, privateKey: server, peerPublicKey: client.publicKey.rawRepresentation,
        credential: credential, transcript: Data("hello".utf8)
    )
    #expect(clientKeys.send.withUnsafeBytes { Data($0) } == serverKeys.receive.withUnsafeBytes { Data($0) })
    #expect(clientKeys.receive.withUnsafeBytes { Data($0) } == serverKeys.send.withUnsafeBytes { Data($0) })
}

@Test func replayedCounterIsRejected() throws {
    let sendKey = SymmetricKey(data: Data(repeating: 1, count: 32))
    let receiveKey = SymmetricKey(data: Data(repeating: 2, count: 32))
    var sender = RemoteSessionCrypto(sendKey: sendKey, receiveKey: receiveKey, noncePrefix: 7)
    var receiver = RemoteSessionCrypto(sendKey: receiveKey, receiveKey: sendKey, noncePrefix: 9)
    let sealed = try sender.seal(.ping(1))
    _ = try receiver.open(sealed)
    #expect(throws: RemoteProtocolError.self) { try receiver.open(sealed) }
}
```

- [ ] **Step 3: Run focused tests and verify missing symbols**

Run: `rtk swift test --package-path Modules --filter 'Remote(FrameCodec|SessionCrypto)Tests'`

Expected: FAIL because `RemoteTransport` and its types do not exist.

- [ ] **Step 4: Add the RemoteTransport product and implementation**

Add a product and target depending on `RemoteCore`:

```swift
.library(name: "RemoteTransport", targets: ["RemoteTransport"])
.target(name: "RemoteTransport", dependencies: ["RemoteCore"])
```

Implement `RemoteFrameCodec` with a four-byte big-endian payload length followed by JSON-encoded `RemoteMessage`; buffer incomplete bytes and decode all complete frames in order. Reject payloads above 4 MiB before allocation or decoding.

Implement a 12-character base-32 `PairingCode` generator using `SystemRandomNumberGenerator`, excluding `0/O/1/I/L`, and an injected generator for deterministic tests.

Implement `RemoteSessionCrypto` with these boundaries:

```swift
public enum RemotePeerRole: Sendable { case client, server }
public struct RemoteDirectionalKeys: Sendable { public let send: SymmetricKey; public let receive: SymmetricKey }

public struct RemoteEncryptedFrame: Codable, Equatable, Sendable {
    public let noncePrefix: UInt32
    public let counter: UInt64
    public let ciphertext: Data
}

public struct RemoteSessionCrypto: Sendable {
    public init(sendKey: SymmetricKey, receiveKey: SymmetricKey, noncePrefix: UInt32)

    public static func makePairingProof(
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        pairingCode: String,
        transcript: Data
    ) throws -> Data

    public static func deriveSessionKeys(
        role: RemotePeerRole,
        privateKey: P256.KeyAgreement.PrivateKey,
        peerPublicKey: Data,
        credential: Data,
        transcript: Data
    ) throws -> RemoteDirectionalKeys

    public mutating func seal(_ message: RemoteMessage) throws -> RemoteEncryptedFrame
    public mutating func open(_ frame: RemoteEncryptedFrame) throws -> RemoteMessage
}
```

Derive labeled directional keys with HKDF-SHA256, use AES-GCM, construct nonces from a random 32-bit prefix plus a 64-bit counter, and reject any received counter not strictly greater than the previous counter.

- [ ] **Step 5: Run transport and complete package tests**

Run: `rtk swift test --package-path Modules --filter 'Remote(FrameCodec|SessionCrypto)Tests'`

Expected: PASS.

Run: `rtk swift test --package-path Modules`

Expected: PASS with all existing module tests.

- [ ] **Step 6: Commit secure transport**

```bash
rtk git add Modules/Package.swift Modules/Sources/RemoteTransport Modules/Tests/ModulesTests/RemoteFrameCodecTests.swift Modules/Tests/ModulesTests/RemoteSessionCryptoTests.swift
rtk git commit -m "feat: add secure remote transport primitives"
```

### Task 3: iOS app and test-target scaffold

**Files:**
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`
- Create: `OnlySwitch.xcodeproj/xcshareddata/xcschemes/OnlySwitchRemote.xcscheme`
- Create: `OnlySwitchRemote/App/OnlySwitchRemoteApp.swift`
- Create: `OnlySwitchRemote/App/RemoteAppFeature.swift`
- Create: `OnlySwitchRemote/App/RemoteAppView.swift`
- Create: `OnlySwitchRemote/Info.plist`
- Create: `OnlySwitchRemote/OnlySwitchRemote.entitlements`
- Create: `OnlySwitchRemote/Assets.xcassets/Contents.json`
- Create: `OnlySwitchRemote/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `OnlySwitchRemoteTests/RemoteAppSmokeTests.swift`
- Create: `OnlySwitchRemoteTests/RemoteTestValues.swift`

**Interfaces:**
- Consumes: TCA, `RemoteCore`, `RemoteTransport`.
- Produces: buildable `OnlySwitchRemote` and `OnlySwitchRemoteTests` schemes with iOS 18 deployment.

- [ ] **Step 1: Create a minimal failing app smoke test**

```swift
import ComposableArchitecture
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteAppSmokeTests {
    @Test func initialStateRequiresSetupWithoutPairedMacs() {
        let state = RemoteAppFeature.State()
        #expect(state.requiresSetup)
        #expect(state.path.count == 1)
    }
}
```

- [ ] **Step 2: Add both native targets and shared scheme entries**

Update `project.pbxproj` with:

- Product `OnlySwitchRemote.app`, application target, source/resource phases, and a shared scheme.
- Product `OnlySwitchRemoteTests.xctest`, unit-test target hosted by `OnlySwitchRemote`.
- `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `SWIFT_VERSION = 6.0`, `TARGETED_DEVICE_FAMILY = "1,2"`.
- Bundle IDs `jacklandrin.OnlySwitchRemote` and `jacklandrin.OnlySwitchRemoteTests`.
- Package products `ComposableArchitecture`, `RemoteCore`, and `RemoteTransport` linked to both targets as required.
- Generated app icons may remain empty for Debug, but the asset catalog must be assigned.

Do not rewrite or revert the existing build-number edits.

- [ ] **Step 3: Add local-network privacy and Bonjour declarations**

`OnlySwitchRemote/Info.plist` must include:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>OnlySwitch Remote connects to your paired Macs on your local network.</string>
<key>NSBonjourServices</key>
<array><string>_onlyswitch._tcp</string></array>
<key>UILaunchScreen</key><dict/>
```

- [ ] **Step 4: Implement the compiling root shell**

```swift
import ComposableArchitecture
import SwiftUI

@main
struct OnlySwitchRemoteApp: App {
    let store = Store(initialState: RemoteAppFeature.State()) { RemoteAppFeature() }
    var body: some Scene { WindowGroup { RemoteAppView(store: store) } }
}

@Reducer
struct RemoteAppFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        var pairedMacIDs: [UUID] = []
        var requiresSetup: Bool { pairedMacIDs.isEmpty }
        init() { path.append(.setup(.init())) }
    }
    enum Action { case path(StackActionOf<Path>) }
    @Reducer enum Path { case setup(SetupFeature) }
    var body: some ReducerOf<Self> { Reduce { _, _ in .none }.forEach(\.path, action: \.path) }
}

@Reducer
struct SetupFeature {
    @ObservableState struct State: Equatable {}
    enum Action {}
    var body: some ReducerOf<Self> { EmptyReducer() }
}
```

Use a temporary `Text("Settings")` setup destination and an empty dashboard root; later tasks replace them without changing the target shell.

Add shared test constants in `RemoteTestValues.swift` so later tests do not repeat wire IDs:

```swift
import RemoteCore

extension RemoteControlID {
    static let darkMode = Self(kind: .builtIn, value: "2")
    static let mute = Self(kind: .builtIn, value: "8")
    static let airPods = Self(kind: .builtIn, value: "512")
    static let emptyTrash = Self(kind: .builtIn, value: "16384")
}
```

- [ ] **Step 5: Build and run the smoke test on the installed iOS 18.6 simulator**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test`

Expected: PASS `RemoteAppSmokeTests`.

- [ ] **Step 6: Commit the iOS target scaffold**

```bash
rtk git add OnlySwitch.xcodeproj/project.pbxproj OnlySwitch.xcodeproj/xcshareddata/xcschemes/OnlySwitchRemote.xcscheme OnlySwitchRemote OnlySwitchRemoteTests/RemoteAppSmokeTests.swift OnlySwitchRemoteTests/RemoteTestValues.swift
rtk git commit -m "feat: scaffold OnlySwitch Remote iOS app"
```

### Task 4: Mac catalog provider and command router

**Files:**
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`
- Create: `OnlySwitch/Features/RemoteAccess/Catalog/RemoteControlAvailability.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Catalog/RemoteIconAdapter.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Catalog/RemoteCatalogProvider.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Catalog/RemoteCatalogProvider+Live.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Commands/RemoteCommandRouter.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Commands/RemoteCommandRouter+Live.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Commands/RecentRequestCache.swift`
- Create: `OnlySwitchTests/RemoteAccess/RemoteCatalogProviderTests.swift`
- Create: `OnlySwitchTests/RemoteAccess/RemoteCommandRouterTests.swift`
- Create: `OnlySwitchTests/RemoteAccess/RemoteMacTestValues.swift`

**Interfaces:**
- Consumes: `SwitchType`, `SwitchProvider`, `ShortcutsSettingVM.getAllInstalledShortcutName()`, `EvolutionListService.loadEvolutionList`, `EvolutionCommandService`.
- Produces: `RemoteCatalogProvider.catalog/status`, `RemoteCommandRouter.perform`, deterministic request deduplication.

Link `RemoteCore` and `RemoteTransport` to `OnlySwitch` and `OnlySwitchTests`. `RemoteMacTestValues.swift` supplies this fake used by both test files:

```swift
final class FakeSwitch: SwitchProvider, @unchecked Sendable {
    let type: SwitchType
    weak var delegate: SwitchDelegate?
    let visible: Bool
    var status = false
    var operationCount = 0
    init(type: SwitchType, visible: Bool) { self.type = type; self.visible = visible }
    func currentStatus() async -> Bool { status }
    func currentInfo() async -> String { "" }
    func operateSwitch(isOn: Bool) async throws { operationCount += 1; status = isOn }
    func isVisible() -> Bool { visible }
}
```

- [ ] **Step 1: Write failing catalog completeness tests**

```swift
@MainActor
func testCatalogIncludesUnavailableBuiltInsAndAllInstalledContent() async throws {
    let provider = RemoteCatalogProvider(
        builtIns: { [.darkMode, .airPods] },
        makeBuiltIn: { FakeSwitch(type: $0, visible: $0 == .darkMode) },
        shortcutNames: { ["Focus Setup", "Deploy"] },
        evolutions: { [EvolutionItem(id: evolutionID, name: "Deploy Site", controlType: .Button)] }
    )
    let catalog = try await provider.catalog()
    XCTAssertEqual(catalog.count, 5)
    XCTAssertEqual(catalog[id: .init(kind: .builtIn, value: "512")]?.isAvailable, false)
    XCTAssertNotNil(catalog[id: .init(kind: .builtIn, value: "512")]?.unavailableReason)
}
```

- [ ] **Step 2: Write failing router validation and deduplication tests**

```swift
@MainActor
func testDuplicateRequestExecutesOnlyOnce() async {
    let control = FakeSwitch(type: .darkMode, visible: true)
    let router = RemoteCommandRouter(resolveBuiltIn: { _ in control })
    let request = RemoteActionRequest(
        requestID: UUID(), controlID: .init(kind: .builtIn, value: "2"), action: .setState(true)
    )
    _ = await router.perform(request)
    _ = await router.perform(request)
    XCTAssertEqual(control.operationCount, 1)
}
```

- [ ] **Step 3: Run Mac tests and verify missing implementations**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -derivedDataPath /tmp/OnlySwitchDerivedData test -only-testing:OnlySwitchTests/RemoteCatalogProviderTests -only-testing:OnlySwitchTests/RemoteCommandRouterTests`

Expected: FAIL with missing catalog/router types.

- [ ] **Step 4: Implement the testable catalog boundary**

```swift
struct RemoteCatalogProvider: Sendable {
    var catalog: @MainActor @Sendable () async throws -> [RemoteControlDescriptor]
    var status: @MainActor @Sendable (RemoteControlID, UInt64) async throws -> RemoteControlStatus
}

struct RemoteControlAvailability: Equatable, Sendable {
    let isAvailable: Bool
    let reason: String?
}
```

Live catalog behavior:

- Iterate `SwitchType.allCases`, instantiate via `getNewSwitchInstance()`, and map `barInfo()`.
- Map custom AppKit images to resized 60-by-60 PNG; use an SF Symbol name when `barInfo` was created from one.
- Mark invisibility unavailable and provide a control-specific reason for hardware/configuration cases; use `Not available on this Mac` only as the final fallback.
- Load Shortcuts through `getAllInstalledShortcutName()` without reading the menu toggle dictionary.
- Load all Evolution entities through `EvolutionListService.liveValue.loadEvolutionList()`.
- Mark `emptyTrash` and `xcodeCache` destructive.
- Normalize secondary information with `ControlItemSecondaryInformation.subtitle`.

- [ ] **Step 5: Implement the router and bounded request cache**

```swift
actor RecentRequestCache {
    private var order: [UUID] = []
    private var results: [UUID: RemoteActionResult] = [:]
    let capacity: Int
    func result(for id: UUID) -> RemoteActionResult?
    func insert(_ result: RemoteActionResult, for id: UUID)
}

@MainActor
final class RemoteCommandRouter: @unchecked Sendable {
    init(
        resolveBuiltIn: @escaping (UInt64) -> SwitchProvider?,
        runShortcut: @escaping (String) async throws -> Void = { _ in throw RemoteProtocolError(code: .actionNotSupported, message: "Shortcut actions are unavailable") },
        resolveEvolution: @escaping (UUID) -> EvolutionItem? = { _ in nil },
        runEvolution: @escaping (EvolutionItem, RemoteControlAction) async throws -> Void = { _, _ in throw RemoteProtocolError(code: .actionNotSupported, message: "Evolution actions are unavailable") },
        cache: RecentRequestCache = .init(capacity: 512)
    )
    func perform(_ request: RemoteActionRequest) async -> RemoteActionResult
}
```

Resolve built-ins by raw value and call `operateSwitch(isOn:)`; run Shortcuts by exact name; resolve Evolutions by UUID and invoke the appropriate on/off/single command. Validate behavior/action compatibility and availability before invocation. Cache every terminal result by request ID with a capacity of 512.

- [ ] **Step 6: Run catalog/router tests and the macOS build**

Run the focused test command from Step 3.

Expected: PASS.

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx -derivedDataPath /tmp/OnlySwitchDerivedData build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit the Mac bridge**

```bash
rtk git add OnlySwitch.xcodeproj/project.pbxproj OnlySwitch/Features/RemoteAccess/Catalog OnlySwitch/Features/RemoteAccess/Commands OnlySwitchTests/RemoteAccess
rtk git commit -m "feat: bridge Mac controls to remote protocol"
```

### Task 5: Mac credentials, listener, sessions, and subscriptions

**Files:**
- Create: `OnlySwitch/Features/RemoteAccess/Host/RemoteCredentialStore.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Host/RemoteHostConfiguration.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Host/RemotePeerSession.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Host/RemoteStatusScheduler.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Host/RemoteHost.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Host/RemoteHostClient.swift`
- Create: `OnlySwitchTests/RemoteAccess/RemoteCredentialStoreTests.swift`
- Create: `OnlySwitchTests/RemoteAccess/RemoteHostIntegrationTests.swift`
- Create: `OnlySwitchTests/RemoteAccess/RemoteHostTestClient.swift`

**Interfaces:**
- Consumes: Remote transport primitives, catalog provider, command router.
- Produces: `RemoteHost.start/stop/startPairing/revoke`, `RemoteHost.events`, paired-device records, authenticated catalog/action sessions.

Define the host value types before the actor:

```swift
struct RemoteHostConfiguration: Equatable, Sendable {
    var displayName: String
    var serviceType = "_onlyswitch._tcp"
    var port: UInt16 = 0
}

struct PairingWindow: Equatable, Sendable {
    let code: String
    let expiresAt: Date
}

enum HostStatus: Equatable, Sendable { case stopped; case starting; case listening(port: UInt16); case failed(String) }

enum RemoteHostEvent: Equatable, Sendable {
    case statusChanged(HostStatus)
    case pairingChanged(PairingWindow?)
    case devicesChanged([PairedRemoteDevice])
    case connectionCountChanged(Int)
}
```

- [ ] **Step 1: Write failing credential lifecycle tests**

```swift
@Test func revokingOneDevicePreservesOtherCredentials() async throws {
    let store = RemoteCredentialStore.inMemory()
    try await store.save(PairedRemoteDevice(id: firstID, name: "iPhone", credential: Data(repeating: 1, count: 32), createdAt: .now, lastConnectedAt: nil))
    try await store.save(PairedRemoteDevice(id: secondID, name: "iPad", credential: Data(repeating: 2, count: 32), createdAt: .now, lastConnectedAt: nil))
    try await store.delete(firstID)
    #expect(try await store.load(firstID) == nil)
    #expect(try await store.load(secondID) != nil)
}
```

- [ ] **Step 2: Write a failing loopback pairing/action test**

The test starts `RemoteHost` on an ephemeral TCP port with a fixed pairing code, connects a test client, completes pairing and authentication, requests a catalog, subscribes to Dark Mode, sends one request twice, and asserts one fake operation plus two identical results.

```swift
let control = FakeSwitch(type: .darkMode, visible: true)
let router = await MainActor.run { RemoteCommandRouter(resolveBuiltIn: { _ in control }) }
let descriptor = RemoteControlDescriptor(
    id: .init(kind: .builtIn, value: "2"), title: "Dark Mode", behavior: .switch,
    icon: .systemSymbol("moon"), isAvailable: true, unavailableReason: nil,
    isDestructive: false, supportsStatus: true, supportsSecondaryInformation: false
)
let host = RemoteHost.testing(catalog: [descriptor], router: router, pairingCode: "ABCDEFGH2345")
let endpoint = try await host.startForTesting(port: 0)
let client = try await RemoteHostTestClient.connect(to: endpoint)
try await client.pair(code: "ABCDEFGH2345")
#expect(try await client.catalog().contains { $0.title == "Dark Mode" })
let request = RemoteActionRequest(
    requestID: UUID(), controlID: .init(kind: .builtIn, value: "2"), action: .setState(true)
)
let first = try await client.send(request)
let second = try await client.send(request)
#expect(first == second)
#expect(control.operationCount == 1)
```

`RemoteHostTestClient.swift` is a test-only Network.framework client with these concrete methods; it uses the production frame/crypto types and an in-memory credential after `pair`:

```swift
actor RemoteHostTestClient {
    static func connect(to endpoint: NWEndpoint) async throws -> Self
    func pair(code: String) async throws
    func catalog() async throws -> [RemoteControlDescriptor]
    func subscribe(_ ids: Set<RemoteControlID>) async throws
    func send(_ request: RemoteActionRequest) async throws -> RemoteActionResult
}
```

- [ ] **Step 3: Run focused host tests and verify failure**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -derivedDataPath /tmp/OnlySwitchDerivedData test -only-testing:OnlySwitchTests/RemoteCredentialStoreTests -only-testing:OnlySwitchTests/RemoteHostIntegrationTests`

Expected: FAIL with missing host types.

- [ ] **Step 4: Implement Keychain credentials and pairing state**

Use a dedicated Keychain service `jacklandrin.OnlySwitch.remote.devices`. Store one Codable record per device ID containing the 32-byte credential, device display name, creation date, and last-connected date. Store the Mac installation UUID under `jacklandrin.OnlySwitch.remote.identity`. Set `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and never synchronize these items.

```swift
struct PairedRemoteDevice: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let credential: Data
    let createdAt: Date
    var lastConnectedAt: Date?
}

actor RemoteCredentialStore {
    static func live(service: String) -> RemoteCredentialStore
    static func inMemory() -> RemoteCredentialStore
    func save(_ device: PairedRemoteDevice) async throws
    func load(_ id: UUID) async throws -> PairedRemoteDevice?
    func loadAll() async throws -> [PairedRemoteDevice]
    func delete(_ id: UUID) async throws
}
```

- [ ] **Step 5: Implement the host actor and peer state machine**

```swift
actor RemoteHost {
    static func testing(
        catalog: [RemoteControlDescriptor],
        router: RemoteCommandRouter,
        pairingCode: String
    ) -> RemoteHost
    func start(configuration: RemoteHostConfiguration) async throws
    func startForTesting(port: UInt16) async throws -> NWEndpoint
    func stop() async
    func startPairing() async -> PairingWindow
    func cancelPairing() async
    func revoke(deviceID: UUID) async throws
    func pairedDevices() async throws -> [PairedRemoteDevice]
    nonisolated var events: AsyncStream<RemoteHostEvent> { get }
}
```

Expose the host to TCA settings through one dependency boundary:

```swift
@DependencyClient
struct RemoteHostClient: Sendable {
    var start: @Sendable (RemoteHostConfiguration) async throws -> Void
    var stop: @Sendable () async -> Void
    var startPairing: @Sendable () async throws -> PairingWindow
    var cancelPairing: @Sendable () async -> Void
    var revoke: @Sendable (UUID) async throws -> Void
    var pairedDevices: @Sendable () async throws -> [PairedRemoteDevice]
    var events: @Sendable () -> AsyncStream<RemoteHostEvent> = { AsyncStream { $0.finish() } }
}

extension RemoteHostClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { Self() }
}

extension DependencyValues {
    var remoteHost: RemoteHostClient { get { self[RemoteHostClient.self] } set { self[RemoteHostClient.self] = newValue } }
}
```

`NWListener` advertises `_onlyswitch._tcp`. `RemotePeerSession` permits only hello/pairing/authentication before authentication; after authentication it decrypts messages and routes catalog/subscription/action traffic. Close on invalid framing, proof, replay, oversized icon, or protocol mismatch. Pairing expires after five minutes or five failed proofs.

- [ ] **Step 6: Implement coalesced status subscriptions**

`RemoteStatusScheduler` unions IDs across sessions, starts one task per ID, prevents overlapping refreshes, emits immediate status, refreshes every three seconds while subscribed, and reacts immediately to `.changeSettings` and `.refreshSingleSwitchStatus`. Cancel the task when no sessions subscribe.

- [ ] **Step 7: Run host tests and complete macOS tests**

Run the focused command from Step 3, then:

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -derivedDataPath /tmp/OnlySwitchDerivedData test`

Expected: PASS.

- [ ] **Step 8: Commit the Mac host**

```bash
rtk git add OnlySwitch/Features/RemoteAccess/Host OnlySwitchTests/RemoteAccess
rtk git commit -m "feat: host authenticated remote sessions on Mac"
```

### Task 6: Mac Remote Access settings and lifecycle

**Files:**
- Modify: `OnlySwitch/Features/Settings/SettingsView/SettingsVM.swift`
- Modify: `OnlySwitch/Features/Settings/SettingsView/SettingsView.swift`
- Modify: `OnlySwitch/AppDelegate.swift`
- Modify: `OnlySwitch/Info.plist`
- Create: `OnlySwitch/Features/RemoteAccess/Settings/RemoteAccessSettingsFeature.swift`
- Create: `OnlySwitch/Features/RemoteAccess/Settings/RemoteAccessSettingsView.swift`
- Create: `OnlySwitchTests/RemoteAccess/RemoteAccessSettingsFeatureTests.swift`

**Interfaces:**
- Consumes: `RemoteHost` dependency.
- Produces: dedicated `iOS Remote` settings item and persisted enable/display-name configuration.

- [ ] **Step 1: Write failing settings reducer tests**

```swift
@MainActor
func testEnablingStartsHostAndPairingPublishesCode() async {
    let store = TestStore(initialState: RemoteAccessSettingsFeature.State()) {
        RemoteAccessSettingsFeature()
    } withDependencies: {
        $0.remoteHost = RemoteHostClient(
            start: { _ in },
            stop: {},
            startPairing: { PairingWindow(code: "ABCDEFGH2345", expiresAt: .now.addingTimeInterval(300)) },
            cancelPairing: {},
            revoke: { _ in },
            pairedDevices: { [] },
            events: { AsyncStream { $0.finish() } }
        )
    }
    await store.send(.setEnabled(true)) { $0.isEnabled = true }
    await store.receive(.hostStarted)
    await store.send(.startPairingTapped)
    await store.receive(\.pairingStarted) { $0.pairingCode = "ABCDEFGH2345" }
}
```

- [ ] **Step 2: Run the focused test and verify missing feature**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -derivedDataPath /tmp/OnlySwitchDerivedData test -only-testing:OnlySwitchTests/RemoteAccessSettingsFeatureTests`

Expected: FAIL with missing feature/client.

- [ ] **Step 3: Implement reducer state and dependency**

```swift
@Reducer
struct RemoteAccessSettingsFeature {
    @ObservableState struct State: Equatable {
        var isEnabled = false
        var displayName = ProcessInfo.processInfo.hostName
        var hostStatus: HostStatus = .stopped
        var pairingCode: String?
        var pairingExpiresAt: Date?
        var pairedDevices: IdentifiedArrayOf<PairedRemoteDeviceSummary> = []
        var alert: AlertState<Action.Alert>?
    }
    enum Action { case task; case setEnabled(Bool); case hostStarted; case displayNameChanged(String); case startPairingTapped; case pairingStarted(PairingWindow); case revoke(UUID); case alert(PresentationAction<Alert>)
        enum Alert: Equatable { case confirmRevoke(UUID) }
    }
}
```

Persist enablement and display name in `UserDefaults`, but keep credentials in Keychain. Subscribe to host events to update connection count, pairing expiry, and device last-connected dates.

- [ ] **Step 4: Build the settings page**

Use a SwiftUI `Form` with Remote Access toggle, display-name field, status, pairing code with countdown/cancel, and paired-device rows with revoke confirmation. Pairing codes must use monospaced text and must not support copying into logs or analytics.

Add `.iOSRemote = "iOS Remote"` to `SettingsItem`, include it in `SettingsVM.settingItems`, and route it in `SettingsView.page(item:)`.

- [ ] **Step 5: Integrate app lifecycle and Bonjour declaration**

Add `_onlyswitch._tcp` to `NSBonjourServices` in the Mac `Info.plist`. During app startup, start the host only when enabled. Stop it during termination. `AppDelegate` should call a `RemoteAccessController`; it must not own listener/session logic.

- [ ] **Step 6: Run settings tests and macOS build**

Run the focused test from Step 2.

Expected: PASS.

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx -derivedDataPath /tmp/OnlySwitchDerivedData build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit Mac settings**

```bash
rtk git add OnlySwitch/AppDelegate.swift OnlySwitch/Info.plist OnlySwitch/Features/Settings/SettingsView OnlySwitch/Features/RemoteAccess/Settings OnlySwitchTests/RemoteAccess
rtk git commit -m "feat: add Mac settings for iOS remote access"
```

### Task 7: iOS persistence, Keychain, discovery, and connections

**Files:**
- Create: `OnlySwitchRemote/Models/PairedMac.swift`
- Create: `OnlySwitchRemote/Models/MacDashboardLayout.swift`
- Create: `OnlySwitchRemote/Dependencies/RemotePersistenceClient.swift`
- Create: `OnlySwitchRemote/Dependencies/RemoteKeychainClient.swift`
- Create: `OnlySwitchRemote/Dependencies/RemoteConnectionClient.swift`
- Create: `OnlySwitchRemote/Dependencies/RemoteConnectionClient+Live.swift`
- Create: `OnlySwitchRemote/Dependencies/RemoteConnectionCoordinator.swift`
- Create: `OnlySwitchRemote/Dependencies/RemoteConnectionEvent.swift`
- Create: `OnlySwitchRemoteTests/RemotePersistenceClientTests.swift`
- Create: `OnlySwitchRemoteTests/RemoteConnectionClientTests.swift`

**Interfaces:**
- Produces: `PairedMac`, `MacDashboardLayout`, TCA dependency clients, async discovery/session events.
- Consumes: Remote transport/core and Foundation/Security/Network.

Use this application-facing event contract:

```swift
struct DiscoveredMac: Equatable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let endpoint: NWEndpoint
    let protocolVersion: RemoteProtocolVersion
}

enum RemoteConnectionEvent: Equatable, Sendable {
    case connecting(UUID)
    case authenticated(UUID)
    case offline(UUID, String?)
    case revoked(UUID)
    case catalog(UUID, UInt64, [RemoteControlDescriptor])
    case status(UUID, RemoteControlStatus)
    case action(UUID, RemoteActionResult)
}

enum DiscoveryEvent: Equatable, Sendable {
    case added(DiscoveredMac)
    case removed(UUID)
}
```

- [ ] **Step 1: Write failing per-Mac layout persistence tests**

```swift
@Test func layoutsRemainIndependentPerMac() async throws {
    let client = RemotePersistenceClient.inMemory()
    try await client.saveLayout(.init(macID: firstMac, selectedControlIDs: [.darkMode], order: [.darkMode]))
    try await client.saveLayout(.init(macID: secondMac, selectedControlIDs: [.mute], order: [.mute]))
    #expect(try await client.loadLayout(firstMac)?.selectedControlIDs == [.darkMode])
    #expect(try await client.loadLayout(secondMac)?.selectedControlIDs == [.mute])
}
```

- [ ] **Step 2: Write failing discovery/session event tests**

```swift
@Test func selectingMacClosesPreviousSessionBeforeConnectingNewOne() async {
    let recorder = ConnectionOperationRecorder()
    let coordinator = RemoteConnectionCoordinator(
        connect: { await recorder.record(.connect($0.id)) },
        disconnect: { await recorder.record(.disconnect($0)) }
    )
    await coordinator.select(PairedMac(id: firstMac, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false))
    await coordinator.select(PairedMac(id: secondMac, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false))
    #expect(await recorder.events == [.connect(firstMac), .disconnect(firstMac), .connect(secondMac)])
}
```

Define this support directly in `RemoteConnectionClientTests.swift`:

```swift
private enum ConnectionOperation: Equatable, Sendable { case connect(UUID); case disconnect(UUID) }
private actor ConnectionOperationRecorder {
    private(set) var events: [ConnectionOperation] = []
    func record(_ event: ConnectionOperation) { events.append(event) }
}
```

Production `RemoteConnectionCoordinator` has this exact boundary and enforces disconnect-before-connect:

```swift
actor RemoteConnectionCoordinator {
    init(
        connect: @escaping @Sendable (PairedMac) async -> Void,
        disconnect: @escaping @Sendable (UUID) async -> Void
    )
    func select(_ mac: PairedMac?) async
}
```

- [ ] **Step 3: Run iOS tests and verify missing clients**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:OnlySwitchRemoteTests/RemotePersistenceClientTests -only-testing:OnlySwitchRemoteTests/RemoteConnectionClientTests`

Expected: FAIL with missing models/clients.

- [ ] **Step 4: Implement models and persistence**

```swift
struct PairedMac: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var lastEndpointDescription: String?
    var lastConnectedAt: Date?
    var requiresPairing: Bool
}

struct MacDashboardLayout: Codable, Equatable, Sendable {
    let macID: UUID
    var selectedControlIDs: Set<RemoteControlID>
    var order: [RemoteControlID]
}
```

Store small preferences in `UserDefaults`. Store catalog/status cache as atomic JSON files under `Application Support/OnlySwitchRemote/<mac-id>/`. Store each 32-byte credential in Keychain service `jacklandrin.OnlySwitchRemote.macs` keyed by Mac UUID with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and synchronization disabled. Forgetting a Mac removes all three stores.

Expose persistence through this dependency:

```swift
@DependencyClient
struct RemotePersistenceClient: Sendable {
    var loadPairedMacs: @Sendable () async throws -> [PairedMac] = { [] }
    var savePairedMacs: @Sendable ([PairedMac]) async throws -> Void
    var loadSelectedMacID: @Sendable () async throws -> UUID?
    var saveSelectedMacID: @Sendable (UUID?) async throws -> Void
    var loadLayout: @Sendable (UUID) async throws -> MacDashboardLayout?
    var saveLayout: @Sendable (MacDashboardLayout) async throws -> Void
    var forgetMac: @Sendable (UUID) async throws -> Void
}

extension RemotePersistenceClient {
    static func inMemory() -> Self
}

extension RemotePersistenceClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { Self() }
}

extension DependencyValues {
    var remotePersistence: RemotePersistenceClient { get { self[RemotePersistenceClient.self] } set { self[RemotePersistenceClient.self] = newValue } }
}
```

Keep Keychain operations separate from layout persistence:

```swift
@DependencyClient
struct RemoteKeychainClient: Sendable {
    var saveCredential: @Sendable (UUID, Data) async throws -> Void
    var loadCredential: @Sendable (UUID) async throws -> Data?
    var deleteCredential: @Sendable (UUID) async throws -> Void
}

extension RemoteKeychainClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { Self() }
}

extension DependencyValues {
    var remoteKeychain: RemoteKeychainClient { get { self[RemoteKeychainClient.self] } set { self[RemoteKeychainClient.self] = newValue } }
}
```

- [ ] **Step 5: Implement the connection client API**

```swift
@DependencyClient
struct RemoteConnectionClient: Sendable {
    var discover: @Sendable () -> AsyncStream<DiscoveryEvent> = { AsyncStream { $0.finish() } }
    var pair: @Sendable (DiscoveredMac, String, String) async throws -> PairedMac
    var select: @Sendable (PairedMac?) async -> Void
    var events: @Sendable () -> AsyncStream<RemoteConnectionEvent> = { AsyncStream { $0.finish() } }
    var subscribe: @Sendable (Set<RemoteControlID>) async throws -> Void
    var send: @Sendable (RemoteActionRequest) async throws -> RemoteActionResult
}

extension RemoteConnectionClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { Self() }
}

extension DependencyValues {
    var remoteConnection: RemoteConnectionClient { get { self[RemoteConnectionClient.self] } set { self[RemoteConnectionClient.self] = newValue } }
}
```

The live client wraps one `NWBrowser` and one selected-Mac connection actor. It emits discovery, connecting/authenticated/offline/revoked, catalog, status, and action events. Use bounded exponential retry while foregrounded; `select(nil)` and backgrounding cancel it.

- [ ] **Step 6: Run focused iOS tests**

Run the command from Step 3.

Expected: PASS.

- [ ] **Step 7: Commit iOS data and connection clients**

```bash
rtk git add OnlySwitchRemote/Models OnlySwitchRemote/Dependencies OnlySwitchRemoteTests
rtk git commit -m "feat: add iOS remote persistence and connections"
```

### Task 8: First-run navigation and pairing feature

**Files:**
- Modify: `OnlySwitchRemote/App/RemoteAppFeature.swift`
- Modify: `OnlySwitchRemote/App/RemoteAppView.swift`
- Create: `OnlySwitchRemote/Features/Settings/SettingsFeature.swift`
- Create: `OnlySwitchRemote/Features/Pairing/PairingFeature.swift`
- Create: `OnlySwitchRemote/Features/Pairing/PairingView.swift`
- Create: `OnlySwitchRemoteTests/RemoteAppFeatureTests.swift`
- Create: `OnlySwitchRemoteTests/PairingFeatureTests.swift`

**Interfaces:**
- Consumes: persistence, Keychain, connection client.
- Produces: required setup routing, discovery list, code entry, paired Mac selection.

- [ ] **Step 1: Write failing first-launch navigation tests**

```swift
@MainActor
@Test func firstLaunchPushesNonDismissibleSettings() async {
    let store = TestStore(initialState: RemoteAppFeature.State()) { RemoteAppFeature() }
    await store.send(.task)
    await store.receive(.loadedPairedMacs([])) {
        $0.path.append(.settings(.init(isSetupRequired: true)))
    }
}

@MainActor
@Test func completedPairingPopsToDashboard() async {
    let mac = PairedMac(id: UUID(), displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
    var initialState = RemoteAppFeature.State()
    initialState.path.append(.settings(.init(isSetupRequired: true)))
    let settingsID = initialState.path.ids.first!
    let store = TestStore(initialState: initialState) { RemoteAppFeature() }
    await store.send(.path(.element(id: settingsID, action: .settings(.delegate(.paired(mac)))))) {
        $0.selectedMacID = mac.id
        $0.path.removeAll()
    }
}
```

- [ ] **Step 2: Write failing pairing success/expiry tests**

Test that discovery updates by stable Mac UUID, a 12-character code enables Pair, success delegates the new Mac, and `pairingExpired` leaves the user on code entry with a specific error.

- [ ] **Step 3: Run focused tests and verify missing behavior**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:OnlySwitchRemoteTests/RemoteAppFeatureTests -only-testing:OnlySwitchRemoteTests/PairingFeatureTests`

Expected: FAIL assertions or missing types.

- [ ] **Step 4: Implement PairingFeature**

```swift
@Reducer
struct PairingFeature {
    @ObservableState struct State: Equatable {
        var discoveredMacs: IdentifiedArrayOf<DiscoveredMac> = []
        var selectedMacID: UUID?
        var code = ""
        var isPairing = false
        var errorMessage: String?
    }
    enum Action { case task; case discovery(DiscoveryEvent); case selectMac(UUID); case codeChanged(String); case pairTapped; case pairingResponse(Result<PairedMac, RemoteProtocolError>); case delegate(Delegate) }
    enum Delegate { case paired(PairedMac) }
}
```

Normalize code to uppercase allowed characters, limit it to 12, disable Pair until complete, and cancel discovery when dismissed.

- [ ] **Step 5: Implement root navigation**

Dashboard is always the `NavigationStack` root. On task, load paired Macs. Push setup Settings with back navigation hidden if none exist; otherwise select the persisted or first Mac. Pairing success persists selection and removes the setup destination. Forgetting the final Mac pushes setup again.

Replace the scaffold action/path contract with:

```swift
enum Action {
    case task
    case loadedPairedMacs([PairedMac])
    case path(StackActionOf<Path>)
}

@Reducer
enum Path {
    case settings(SettingsFeature)
}
```

Create the initial Settings coordinator here; Task 9 expands its catalog and device-management state without changing its delegate contract:

```swift
@Reducer
struct SettingsFeature {
    @ObservableState struct State: Equatable {
        let isSetupRequired: Bool
        @Presents var pairing: PairingFeature.State?
    }
    enum Action {
        case pairAnotherTapped
        case pairing(PresentationAction<PairingFeature.Action>)
        case delegate(Delegate)
    }
    enum Delegate: Equatable { case paired(PairedMac); case allMacsRemoved }
}
```

- [ ] **Step 6: Build accessible PairingView**

Use a discoverable Mac list, connection/help text, a monospaced pairing-code field with `.textInputAutocapitalization(.characters)`, and a clear progress/error state. VoiceOver labels must distinguish discovered name, paired state, and selection.

- [ ] **Step 7: Run focused tests and commit**

Run the command from Step 3.

Expected: PASS.

```bash
rtk git add OnlySwitchRemote/App OnlySwitchRemote/Features/Pairing OnlySwitchRemote/Features/Settings/SettingsFeature.swift OnlySwitchRemoteTests
rtk git commit -m "feat: add first-run Mac pairing flow"
```

### Task 9: Settings, Mac management, and per-Mac tile layouts

**Files:**
- Modify: `OnlySwitchRemote/Features/Settings/SettingsFeature.swift`
- Create: `OnlySwitchRemote/Features/Settings/SettingsView.swift`
- Create: `OnlySwitchRemote/Features/Settings/MacManagementFeature.swift`
- Create: `OnlySwitchRemote/Features/Settings/MacManagementView.swift`
- Create: `OnlySwitchRemote/Features/Settings/ControlSelectionRow.swift`
- Create: `OnlySwitchRemoteTests/SettingsFeatureTests.swift`
- Create: `OnlySwitchRemoteTests/MacManagementFeatureTests.swift`

**Interfaces:**
- Consumes: paired Macs, catalogs, persistence, connection client, PairingFeature.
- Produces: Mac selection/forgetting and ordered selected IDs per Mac.

- [ ] **Step 1: Write failing per-Mac selection and reorder tests**

```swift
@MainActor
@Test func switchingMacLoadsItsOwnLayout() async {
    let first = PairedMac(id: firstID, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
    let second = PairedMac(id: secondID, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
    let layout = MacDashboardLayout(macID: secondID, selectedControlIDs: [.mute], order: [.mute])
    let state = SettingsFeature.State(
        isSetupRequired: false, pairedMacs: [first, second], selectedMacID: firstID
    )
    let store = TestStore(initialState: state) { SettingsFeature() } withDependencies: {
        $0.remotePersistence.loadLayout = { _ in layout }
    }
    await store.send(.selectedMacChanged(secondID)) { $0.selectedMacID = secondID }
    await store.receive(.layoutLoaded(layout)) { $0.selectedControlIDs = [.mute]; $0.order = [.mute] }
}

@MainActor
@Test func unavailableControlCanRemainSelected() async {
    let unavailable = RemoteControlDescriptor(
        id: .airPods, title: "AirPods", behavior: .player,
        icon: .systemSymbol("airpodspro"), isAvailable: false,
        unavailableReason: "Configure AirPods on the Mac", isDestructive: false,
        supportsStatus: true, supportsSecondaryInformation: true
    )
    let state = SettingsFeature.State(
        isSetupRequired: false, pairedMacs: [], selectedMacID: nil,
        catalog: IdentifiedArray(uniqueElements: [unavailable]),
        selectedControlIDs: [], order: []
    )
    let store = TestStore(initialState: state) { SettingsFeature() }
    await store.send(.toggleControl(unavailable.id, true)) { $0.selectedControlIDs.insert(unavailable.id) }
}
```

- [ ] **Step 2: Write failing forget-last-Mac delegation test**

Assert that confirmed forgetting deletes credential/cache/layout, selects another Mac when present, and delegates `.allMacsRemoved` when the last Mac is forgotten.

- [ ] **Step 3: Run focused tests and verify missing features**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:OnlySwitchRemoteTests/SettingsFeatureTests -only-testing:OnlySwitchRemoteTests/MacManagementFeatureTests`

Expected: FAIL with missing settings features.

- [ ] **Step 4: Implement SettingsFeature state flow**

```swift
@Reducer
struct SettingsFeature {
    @ObservableState struct State: Equatable {
        let isSetupRequired: Bool
        var pairedMacs: IdentifiedArrayOf<PairedMac>
        var selectedMacID: UUID?
        var catalog: IdentifiedArrayOf<RemoteControlDescriptor>
        var selectedControlIDs: Set<RemoteControlID>
        var order: [RemoteControlID]
        @Presents var destination: Destination.State?

        init(
            isSetupRequired: Bool,
            pairedMacs: IdentifiedArrayOf<PairedMac>,
            selectedMacID: UUID?,
            catalog: IdentifiedArrayOf<RemoteControlDescriptor> = [],
            selectedControlIDs: Set<RemoteControlID> = [],
            order: [RemoteControlID] = []
        ) {
            self.isSetupRequired = isSetupRequired
            self.pairedMacs = pairedMacs
            self.selectedMacID = selectedMacID
            self.catalog = catalog
            self.selectedControlIDs = selectedControlIDs
            self.order = order
        }
    }
    enum Action { case task; case selectedMacChanged(UUID); case layoutLoaded(MacDashboardLayout); case catalogUpdated([RemoteControlDescriptor]); case toggleControl(RemoteControlID, Bool); case move(IndexSet, Int); case pairAnotherTapped; case manageMac(UUID); case destination(PresentationAction<Destination.Action>); case delegate(Delegate) }
    enum Delegate: Equatable { case paired(PairedMac); case selectedMacChanged(UUID); case allMacsRemoved }
    @Reducer enum Destination { case pairing(PairingFeature); case macManagement(MacManagementFeature) }
}
```

Persist every toggle and move immediately for the selected Mac. Preserve missing IDs in order, but render only descriptors currently present. Group rows by built-in, Shortcut, and Evolution.

- [ ] **Step 5: Implement settings and management views**

Use a standard `List` with sections `Macs`, `Built-ins`, `Shortcuts`, and `Evolutions`. Show unavailable reason under the title; do not disable its inclusion toggle. Provide Edit mode reorder for selected controls. `Pair Another Mac` presents PairingFeature. Device management displays status/last connected and uses a destructive confirmation dialog before forgetting.

- [ ] **Step 6: Run focused tests and commit**

Run the command from Step 3.

Expected: PASS.

```bash
rtk git add OnlySwitchRemote/Features/Settings OnlySwitchRemoteTests
rtk git commit -m "feat: add per-Mac remote settings and layouts"
```

### Task 10: Dashboard tiles, actions, integration, and final verification

**Files:**
- Create: `OnlySwitchRemote/Features/Dashboard/DashboardFeature.swift`
- Create: `OnlySwitchRemote/Features/Dashboard/DashboardView.swift`
- Create: `OnlySwitchRemote/Features/Dashboard/ControlTileView.swift`
- Create: `OnlySwitchRemote/Features/Dashboard/MacPickerView.swift`
- Modify: `OnlySwitchRemote/App/RemoteAppFeature.swift`
- Modify: `OnlySwitchRemote/App/RemoteAppView.swift`
- Modify: `OnlySwitchRemote/Info.plist`
- Modify: `Localization/Localizable.xcstrings`
- Create: `OnlySwitchRemoteTests/DashboardFeatureTests.swift`
- Create: `OnlySwitchRemoteTests/RemoteEndToEndTests.swift`

**Interfaces:**
- Consumes: selected Mac/layout, connection events, catalog/status, action client.
- Produces: tile-first dashboard, Mac picker, hamburger Settings navigation, authoritative action lifecycle.

- [ ] **Step 1: Write failing dashboard subscription and stale-state tests**

```swift
@MainActor
@Test func taskSubscribesOnlyToSelectedTiles() async {
    let state = DashboardFeature.State(
        pairedMacs: [], selectedMacID: nil, descriptors: [], statuses: [:],
        orderedSelectedIDs: [.darkMode, .mute], requestsInFlight: [], connectionState: .authenticated
    )
    let store = TestStore(initialState: state) { DashboardFeature() }
    await store.send(.task)
    await store.receive(.subscriptionStarted(Set([.darkMode, .mute])))
}

@MainActor
@Test func disconnectMarksStatusStaleAndDisablesActions() async {
    let macID = UUID()
    let status = RemoteControlStatus(
        id: .darkMode, isAvailable: true, unavailableReason: nil, isOn: true,
        secondaryInformation: nil, isProcessing: false, revision: 1, updatedAt: .now
    )
    let state = DashboardFeature.State(
        pairedMacs: [], selectedMacID: macID, descriptors: [],
        statuses: [.darkMode: DashboardFeature.TileStatus(value: status, isStale: false)],
        orderedSelectedIDs: [.darkMode], requestsInFlight: [], connectionState: .authenticated
    )
    let store = TestStore(initialState: state) { DashboardFeature() }
    await store.send(.connectionEvent(.offline(macID, nil))) {
        $0.connectionState = .offline
        $0.statuses[.darkMode]?.isStale = true
    }
    #expect(!store.state.canSendActions)
}
```

- [ ] **Step 2: Write failing destructive and authoritative-action tests**

Test that Empty Trash presents confirmation before sending, non-destructive controls send immediately, a tile remains unchanged while processing, success applies only the returned/pushed status revision, duplicate/older revisions are ignored, and failure restores idle state with an alert.

- [ ] **Step 3: Run dashboard tests and verify missing behavior**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:OnlySwitchRemoteTests/DashboardFeatureTests`

Expected: FAIL with missing dashboard types.

- [ ] **Step 4: Implement DashboardFeature**

```swift
@Reducer
struct DashboardFeature {
    enum ConnectionState: Equatable, Sendable { case idle; case connecting; case authenticated; case offline; case revoked }

    struct TileStatus: Equatable, Sendable {
        var value: RemoteControlStatus
        var isStale: Bool
    }

    @ObservableState struct State: Equatable {
        var pairedMacs: IdentifiedArrayOf<PairedMac>
        var selectedMacID: UUID?
        var descriptors: IdentifiedArrayOf<RemoteControlDescriptor>
        var statuses: [RemoteControlID: TileStatus]
        var orderedSelectedIDs: [RemoteControlID]
        var requestsInFlight: Set<RemoteControlID>
        var connectionState: ConnectionState
        @Presents var alert: AlertState<Action.Alert>?

        init(
            pairedMacs: IdentifiedArrayOf<PairedMac>,
            selectedMacID: UUID?,
            descriptors: IdentifiedArrayOf<RemoteControlDescriptor>,
            statuses: [RemoteControlID: TileStatus],
            orderedSelectedIDs: [RemoteControlID],
            requestsInFlight: Set<RemoteControlID>,
            connectionState: ConnectionState
        ) {
            self.pairedMacs = pairedMacs
            self.selectedMacID = selectedMacID
            self.descriptors = descriptors
            self.statuses = statuses
            self.orderedSelectedIDs = orderedSelectedIDs
            self.requestsInFlight = requestsInFlight
            self.connectionState = connectionState
        }
    }
    enum Action { case task; case subscriptionStarted(Set<RemoteControlID>); case macSelected(UUID); case connectionEvent(RemoteConnectionEvent); case tileTapped(RemoteControlID); case confirmed(RemoteControlID); case actionResponse(RemoteControlID, Result<RemoteActionResult, RemoteProtocolError>); case menuTapped; case alert(PresentationAction<Alert>); case delegate(Delegate)
        enum Alert: Equatable { case confirmDestructive(RemoteControlID) }
    }
    enum Delegate { case openSettings }
}
```

On task or layout change, subscribe to the selected IDs. Use descriptor behavior/current status to create `.setState(!current)` or `.trigger`. Generate one UUID per tap and retain it through retry. Never mutate `isOn` until an authoritative newer revision arrives.

- [ ] **Step 5: Build the adaptive dashboard UI**

`DashboardView` uses `NavigationStack` at the app level, a centered Mac picker, and a top-right labeled `Button("Settings", systemImage: "line.3.horizontal")` whose visible label may be icon-only but retains the accessibility label. Use `LazyVGrid` with two compact columns and adaptive minimum 160-point columns at regular width.

`ControlTileView` displays icon, title, secondary information, unavailable reason, state, and progress. Use `.foregroundStyle`, semantic buttons, Dynamic Type, VoiceOver value/hint, minimum 44-point hit targets, and no animation when Reduce Motion is enabled.

- [ ] **Step 6: Wire app navigation and localized strings**

Connect Dashboard delegate `.openSettings` to push `SettingsFeature.State(isSetupRequired: false)`. Connect Settings delegates for paired/selected/removed Macs back into root and dashboard state. Add all new user-facing strings to `Localization/Localizable.xcstrings`; use existing localization helpers only in the Mac target and native localization in the iOS target.

- [ ] **Step 7: Add the end-to-end test**

Use an in-process loopback host and live iOS connection client to pair, authenticate, receive a catalog, subscribe, trigger a fake Dark Mode control, receive a higher status revision, disconnect, and verify stale disabled UI state. Assert no plaintext credential or pairing code is present in captured frame bytes.

- [ ] **Step 8: Run all package and application tests**

Run: `rtk swift test --package-path Modules`

Expected: PASS.

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -derivedDataPath /tmp/OnlySwitchDerivedData test`

Expected: TEST SUCCEEDED.

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=EA98E245-3E64-468E-B59D-67BDA9E88352' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO test`

Expected: TEST SUCCEEDED on iPhone 16 Pro, iOS 18.6.

- [ ] **Step 9: Verify iPad compilation and both release builds**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -destination 'platform=iOS Simulator,id=7E3B9522-AAB5-494F-9CBF-D70650D3BF09' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED on iPad Pro 11-inch (M4), iOS 18.6.

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Release -sdk macosx -derivedDataPath /tmp/OnlySwitchDerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/OnlySwitchRemoteDerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 10: Audit security, accessibility, and working-tree scope**

Run: `rtk rg -n 'print\(|debugPrint\(|Logger\.|os_log' OnlySwitch/Features/RemoteAccess OnlySwitchRemote Modules/Sources/RemoteTransport`

Expected: no log statement includes code, credential, key, proof, decrypted frame, or payload data.

Run: `rtk git diff --check`

Expected: no whitespace errors.

Run: `rtk git status --short`

Expected: only intended feature files plus the user's pre-existing project version change; verify that no `.superpowers/` companion files are staged.

- [ ] **Step 11: Commit the completed dashboard and integration**

```bash
rtk git add OnlySwitchRemote/App OnlySwitchRemote/Features/Dashboard OnlySwitchRemoteTests Localization/Localizable.xcstrings OnlySwitchRemote/Info.plist
rtk git commit -m "feat: complete OnlySwitch iOS remote dashboard"
```
