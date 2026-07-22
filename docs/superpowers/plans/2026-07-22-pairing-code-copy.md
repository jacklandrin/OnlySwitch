# Pairing Code Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a testable Copy button beside the active pairing code in the Mac app's iOS Remote settings, with temporary Copied feedback.

**Architecture:** Keep pasteboard access behind a TCA dependency declared with the existing remote-settings dependencies. The reducer owns copy success, failure, stale-action handling, and feedback timing; the SwiftUI view only renders state and sends the copy action.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSPasteboard`, The Composable Architecture 1.25.3, Swift Testing

## Global Constraints

- Modify only the Mac app's iOS Remote settings and its focused tests.
- Do not change pairing, discovery, credential, or pairing-code lifetime behavior.
- Do not stage the user's current `OnlySwitch.xcodeproj/project.pbxproj` or `OnlySwitchRemote/Localizable.xcstrings` changes.
- Preserve the accepted Xcode 26.6 macOS test-scanner failure as a documented baseline if it blocks test execution before the focused tests start.

---

### Task 1: Testable Pairing-Code Copy Action

**Files:**
- Modify: `OnlySwitch/Features/RemoteAccess/Settings/RemoteAccessSettingsFeature.swift`
- Modify: `OnlySwitch/Features/RemoteAccess/Settings/RemoteAccessSettingsView.swift`
- Test: `OnlySwitchTests/RemoteAccess/RemoteAccessSettingsFeatureTests.swift`

**Interfaces:**
- Consumes: `State.pairingCode`, `State.alert`, `continuousClock`, and the existing pairing cleanup paths.
- Produces: `RemotePasteboardClient.copy(_:) async -> Bool`, dependency value `remotePasteboard`, state `isPairingCodeCopied`, and actions `copyPairingCodeTapped`, `copyPairingCodeResponse(Bool)`, and `clearPairingCodeCopied`.

- [ ] **Step 1: Write failing reducer tests for success, stale copy, and failure**

Add a small actor recorder and these behaviors to `RemoteAccessSettingsFeatureTests.swift`:

```swift
@Test
func copyingActivePairingCodeShowsTemporaryConfirmation() async {
    let clock = TestClock()
    let pasteboard = RemotePasteboardRecorder(result: true)
    var state = RemoteAccessSettingsFeature.State(isEnabled: true)
    state.pairingCode = "ABCDEFGH2345"
    let store = TestStore(initialState: state) {
        RemoteAccessSettingsFeature()
    } withDependencies: {
        $0.continuousClock = clock
        $0.remotePasteboard = pasteboard.client
    }

    await store.send(.copyPairingCodeTapped)
    await store.receive(.copyPairingCodeResponse(true)) {
        $0.isPairingCodeCopied = true
    }
    #expect(await pasteboard.values == ["ABCDEFGH2345"])

    await clock.advance(by: .seconds(2))
    await store.receive(.clearPairingCodeCopied) {
        $0.isPairingCodeCopied = false
    }
}

@Test
func copyingWithoutActivePairingDoesNothing() async {
    let pasteboard = RemotePasteboardRecorder(result: true)
    let store = TestStore(initialState: RemoteAccessSettingsFeature.State()) {
        RemoteAccessSettingsFeature()
    } withDependencies: {
        $0.remotePasteboard = pasteboard.client
    }

    await store.send(.copyPairingCodeTapped)
    #expect(await pasteboard.values.isEmpty)
}

@Test
func pasteboardFailureKeepsPairingAndShowsError() async {
    let pasteboard = RemotePasteboardRecorder(result: false)
    var state = RemoteAccessSettingsFeature.State(isEnabled: true)
    state.pairingCode = "ABCDEFGH2345"
    let store = TestStore(initialState: state) {
        RemoteAccessSettingsFeature()
    } withDependencies: {
        $0.remotePasteboard = pasteboard.client
    }

    await store.send(.copyPairingCodeTapped)
    await store.receive(.copyPairingCodeResponse(false)) {
        $0.alert = .error("The pairing code couldn’t be copied.")
    }
    #expect(store.state.pairingCode == "ABCDEFGH2345")
}
```

The recorder is:

```swift
private actor RemotePasteboardRecorder {
    let result: Bool
    private(set) var values: [String] = []

    init(result: Bool) { self.result = result }

    nonisolated var client: RemotePasteboardClient {
        RemotePasteboardClient { value in
            await self.copy(value)
        }
    }

    private func copy(_ value: String) -> Bool {
        values.append(value)
        return result
    }
}
```

- [ ] **Step 2: Run the focused test target and verify RED**

Run:

```bash
rtk xcodebuild -project /Users/boliu/Developer/OnlySwitch/.worktrees/ios-remote-control/OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx -only-testing:OnlySwitchTests/RemoteAccessSettingsFeatureTests test
```

Expected: compilation fails because `RemotePasteboardClient`, `remotePasteboard`, copy state, and copy actions do not exist. If the accepted Xcode 26.6 scanner failure occurs first, record that exact baseline and also verify RED with a compile/typecheck route that reaches the new test source.

- [ ] **Step 3: Add the minimal pasteboard dependency and reducer behavior**

In `RemoteAccessSettingsFeature.swift`, import AppKit and define:

```swift
struct RemotePasteboardClient: Sendable {
    var copy: @Sendable (String) async -> Bool
}

extension RemotePasteboardClient: DependencyKey {
    static var liveValue: Self {
        Self { value in
            await MainActor.run {
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(value, forType: .string)
            }
        }
    }

    static var testValue: Self { Self { _ in false } }
}

extension DependencyValues {
    var remotePasteboard: RemotePasteboardClient {
        get { self[RemotePasteboardClient.self] }
        set { self[RemotePasteboardClient.self] = newValue }
    }
}
```

Add `isPairingCodeCopied = false` to state, inject `remotePasteboard`, add the three actions, and add a `pairingCodeCopied` cancellation ID. Implement:

```swift
case .copyPairingCodeTapped:
    guard let code = state.pairingCode else { return .none }
    state.isPairingCodeCopied = false
    return .run { send in
        await send(.copyPairingCodeResponse(await remotePasteboard.copy(code)))
    }

case let .copyPairingCodeResponse(succeeded):
    guard state.pairingCode != nil else { return .none }
    guard succeeded else {
        state.alert = .error("The pairing code couldn’t be copied.".localized())
        return .none
    }
    state.isPairingCodeCopied = true
    return .run { send in
        try await clock.sleep(for: .seconds(2))
        await send(.clearPairingCodeCopied)
    }
    .cancellable(id: CancelID.pairingCodeCopied, cancelInFlight: true)

case .clearPairingCodeCopied:
    state.isPairingCodeCopied = false
    return .none
```

Update `clearPairing(state:)` to set `isPairingCodeCopied = false`. Pairing-end actions may leave a harmless cancellable sleeper; its later clear action is idempotent and contains no side effect.

- [ ] **Step 4: Run the focused reducer tests and verify GREEN**

Run the Step 2 command again.

Expected: the three new reducer tests pass. If Xcode stops at the accepted scanner baseline, confirm the feature and test files compile through the available Mac Release build in Step 6 and report the focused-test limitation honestly.

- [ ] **Step 5: Render the explicit Copy/Copied button**

Replace the pairing code value content in `RemoteAccessSettingsView.swift` with:

```swift
HStack(spacing: 12) {
    Text(code)
        .font(.system(.title2, design: .monospaced))
        .bold()
        .textSelection(.disabled)
        .accessibilityLabel(
            "Pairing Code %@".localizeWithFormat(
                arguments: code.map(String.init).joined(separator: " ")
            )
        )

    Button {
        store.send(.copyPairingCodeTapped)
    } label: {
        Label(
            store.isPairingCodeCopied ? "Copied".localized() : "Copy".localized(),
            systemImage: store.isPairingCodeCopied ? "checkmark" : "doc.on.doc"
        )
    }
    .accessibilityLabel(
        store.isPairingCodeCopied
            ? Text("Pairing code copied".localized())
            : Text("Copy pairing code".localized())
    )
}
```

Do not edit `OnlySwitchRemote/Localizable.xcstrings`; the new Mac strings continue through the existing `.localized()` path.

- [ ] **Step 6: Verify builds and regression suites**

Run:

```bash
rtk xcodebuild -project /Users/boliu/Developer/OnlySwitch/.worktrees/ios-remote-control/OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Release -sdk macosx build
rtk swift test --package-path /Users/boliu/Developer/OnlySwitch/.worktrees/ios-remote-control/Modules
rtk git diff --check
```

Expected: Mac Release build succeeds, Modules tests pass, and `git diff --check` has no output. Confirm the diff excludes `OnlySwitch.xcodeproj/project.pbxproj`, `OnlySwitchRemote/Localizable.xcstrings`, and `.superpowers/`.

- [ ] **Step 7: Commit the implementation**

```bash
git add OnlySwitch/Features/RemoteAccess/Settings/RemoteAccessSettingsFeature.swift OnlySwitch/Features/RemoteAccess/Settings/RemoteAccessSettingsView.swift OnlySwitchTests/RemoteAccess/RemoteAccessSettingsFeatureTests.swift
git commit -m "feat: copy remote pairing code"
```
