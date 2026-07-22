# iOS Remote Dashboard Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a paired Mac discoverable after pairing, constrain long Mac names, use the human-friendly macOS Computer Name by default, and render every dashboard tile icon at one visual size.

**Architecture:** Extend the existing `RemoteConnectionRuntime` discovery-demand rule so a selected Mac owns Bonjour browsing even without a pairing-screen subscriber. Keep UI changes local to the dashboard views, and isolate Mac-name resolution in a pure helper so fallback behavior is testable.

**Tech Stack:** Swift 6.2, SwiftUI, The Composable Architecture, Network.framework Bonjour, SystemConfiguration, Swift Testing, Xcode 26.6.

## Global Constraints

- Support iOS and iPadOS 18 or later.
- Preserve multiple-Mac selection and user-entered custom display names.
- Preserve Dynamic Type and announce full, untruncated names with VoiceOver.
- Do not add third-party dependencies.
- Do not stage `OnlySwitch.xcodeproj/project.pbxproj`, `OnlySwitchRemote/Localizable.xcstrings`, or `.superpowers/`; they contain user-owned changes.
- Treat the known Xcode 26.6 ExtensionFoundation/Network header scanner failure in focused Mac tests as an approved baseline issue; still run the focused test and a Mac Release build.

---

### Task 1: Keep Bonjour Discovery Alive for the Selected Mac

**Files:**
- Modify: `OnlySwitchRemote/Dependencies/RemoteConnectionClient+Live.swift:98-230,530-575,1135-1178`
- Modify: `OnlySwitchRemoteTests/RemoteConnectionClientTests.swift:1586-1630`
- Preserve and include: `OnlySwitchRemote/Features/Pairing/PairingView.swift`

**Interfaces:**
- Consumes: `RemoteConnectionRuntime.discoveryHub.subscriberCount`, `RemoteConnectionRuntime.selected`, and the existing TXT-aware `discoveryDescriptor`.
- Produces: `RemoteConnectionRuntime.needsDiscovery(subscriberCount:selectedMacID:) -> Bool`, used by browser start/stop paths.

- [ ] **Step 1: Add failing discovery-demand tests**

Add these tests beside `discoveryRequestsBonjourTXTRecords`:

```swift
@Test func selectedMacKeepsDiscoveryActiveWithoutPairingSubscriber() {
    #expect(RemoteConnectionRuntime.needsDiscovery(
        subscriberCount: 0,
        selectedMacID: UUID()
    ))
}

@Test func discoveryStopsOnlyWithoutSubscribersOrSelection() {
    #expect(RemoteConnectionRuntime.needsDiscovery(
        subscriberCount: 1,
        selectedMacID: nil
    ))
    #expect(!RemoteConnectionRuntime.needsDiscovery(
        subscriberCount: 0,
        selectedMacID: nil
    ))
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -destination 'platform=iOS Simulator,id=31DCF226-CD61-4F2D-A760-E4C3ACEF1C35' \
  -only-testing:OnlySwitchRemoteTests/RemoteConnectionClientTests test
```

Expected: compilation fails because `RemoteConnectionRuntime` has no member `needsDiscovery`.

- [ ] **Step 3: Implement the discovery-demand rule**

Add the pure rule to `RemoteConnectionRuntime`:

```swift
nonisolated static func needsDiscovery(
    subscriberCount: Int,
    selectedMacID: UUID?
) -> Bool {
    subscriberCount > 0 || selectedMacID != nil
}
```

Change `startDiscovery()` to require foreground state, no existing browser, and discovery demand:

```swift
func startDiscovery() {
    guard foregrounded,
          Self.needsDiscovery(
              subscriberCount: discoveryHub.subscriberCount,
              selectedMacID: selected?.id
          ),
          browser == nil else { return }
    let browser = NWBrowser(for: Self.discoveryDescriptor, using: .tcp)
    // Keep the existing handlers and start call unchanged.
}
```

Change `stopDiscoveryIfUnused()` so removing the pairing subscriber does not clear endpoints for a selected Mac:

```swift
private func stopDiscoveryIfUnused() {
    guard Self.needsDiscovery(
        subscriberCount: discoveryHub.subscriberCount,
        selectedMacID: selected?.id
    ) == false else { return }
    browser?.cancel()
    browser = nil
    browserRetryTask?.cancel()
    browserRetryTask = nil
    browserGeneration &+= 1
    discovered.removeAll()
}
```

After `selected = mac` in `select(_:)`, update browser ownership before reconnecting:

```swift
selected = mac
if mac == nil {
    stopDiscoveryIfUnused()
} else {
    startDiscovery()
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the command from Step 2.

Expected: `RemoteConnectionClientTests` passes, including TXT metadata and selected-Mac discovery demand.

- [ ] **Step 5: Commit only the discovery files**

```bash
rtk git add OnlySwitchRemote/Dependencies/RemoteConnectionClient+Live.swift \
  OnlySwitchRemote/Features/Pairing/PairingView.swift \
  OnlySwitchRemoteTests/RemoteConnectionClientTests.swift
rtk git commit -m "fix: keep selected remote Mac discoverable"
```

---

### Task 2: Constrain the Dashboard Mac Selector

**Files:**
- Modify: `OnlySwitchRemote/Features/Dashboard/MacPickerView.swift`
- Modify: `OnlySwitchRemoteTests/DashboardFeatureTests.swift`

**Interfaces:**
- Consumes: `[PairedMac]`, `selectedMacID: UUID?`, and `select: (UUID) -> Void`.
- Produces: the same `MacPickerView` initializer API and an internal `selectedName` value for regression testing.

- [ ] **Step 1: Add a failing selected-name test**

Add to `DashboardFeatureTests`:

```swift
@Test func macPickerPreservesFullSelectedNameForAccessibility() {
    let longName = "p200300fe5700cdb61cf16e5542f6a6bc.dip0.t-ipconnect.de"
    let selected = PairedMac(
        id: UUID(),
        displayName: longName,
        lastEndpointDescription: nil,
        lastConnectedAt: nil,
        requiresPairing: false
    )
    let picker = MacPickerView(
        macs: [selected],
        selectedMacID: selected.id,
        select: { _ in }
    )

    #expect(picker.selectedName == longName)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -destination 'platform=iOS Simulator,id=31DCF226-CD61-4F2D-A760-E4C3ACEF1C35' \
  -only-testing:OnlySwitchRemoteTests/DashboardFeatureTests/macPickerPreservesFullSelectedNameForAccessibility test
```

Expected: compilation fails because `selectedName` is private.

- [ ] **Step 3: Replace the wrapping picker with a single-line menu**

Keep `selectedName` internal and replace the `Picker` body with:

```swift
var body: some View {
    Menu {
        ForEach(macs) { mac in
            Button {
                select(mac.id)
            } label: {
                if mac.id == selectedMacID {
                    Label(mac.displayName, systemImage: "checkmark")
                } else {
                    Text(mac.displayName)
                }
            }
        }
    } label: {
        HStack(spacing: 8) {
            Image(systemName: "desktopcomputer")
            Text(selectedName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Selected Mac")
    .accessibilityValue(selectedName)
}

var selectedName: String {
    macs.first { $0.id == selectedMacID }?.displayName
        ?? String(localized: "No Mac Selected")
}
```

Remove the unused `selection` binding.

- [ ] **Step 4: Run the focused test and full dashboard tests**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -destination 'platform=iOS Simulator,id=31DCF226-CD61-4F2D-A760-E4C3ACEF1C35' \
  -only-testing:OnlySwitchRemoteTests/DashboardFeatureTests test
```

Expected: all `DashboardFeatureTests` pass.

- [ ] **Step 5: Commit the selector change**

```bash
rtk git add OnlySwitchRemote/Features/Dashboard/MacPickerView.swift \
  OnlySwitchRemoteTests/DashboardFeatureTests.swift
rtk git commit -m "fix: constrain remote Mac selector name"
```

---

### Task 3: Use the macOS Computer Name as the Default

**Files:**
- Modify: `OnlySwitch/Features/RemoteAccess/Settings/RemoteAccessSettingsFeature.swift:1-48`
- Modify: `OnlySwitchTests/RemoteAccess/RemoteAccessSettingsFeatureTests.swift`

**Interfaces:**
- Consumes: `SCDynamicStoreCopyComputerName`, `ProcessInfo.processInfo.hostName`, and the existing persisted display-name preference.
- Produces: `RemoteAccessPreferencesClient.resolvedDefaultDisplayName(computerName:hostName:) -> String`.

- [ ] **Step 1: Add failing name-resolution tests**

Add to `RemoteAccessSettingsFeatureTests`:

```swift
@Test func defaultDisplayNamePrefersComputerName() {
    #expect(RemoteAccessPreferencesClient.resolvedDefaultDisplayName(
        computerName: "  Bo’s Mac Studio  ",
        hostName: "provider.example.net"
    ) == "Bo’s Mac Studio")
}

@Test func defaultDisplayNameFallsBackToHostThenProductName() {
    #expect(RemoteAccessPreferencesClient.resolvedDefaultDisplayName(
        computerName: nil,
        hostName: "  bos-mac-studio.local  "
    ) == "bos-mac-studio.local")
    #expect(RemoteAccessPreferencesClient.resolvedDefaultDisplayName(
        computerName: "   ",
        hostName: "   "
    ) == "OnlySwitch Mac")
}
```

- [ ] **Step 2: Run the focused Mac test and verify RED or the approved scanner baseline**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch \
  -destination 'platform=macOS' \
  -only-testing:OnlySwitchTests/RemoteAccessSettingsFeatureTests test
```

Expected without the Xcode baseline: compilation fails because `resolvedDefaultDisplayName` does not exist. If Xcode 26.6 stops earlier in ExtensionFoundation/Network header scanning, record the exact baseline error and continue with the approved baseline treatment.

- [ ] **Step 3: Implement pure name resolution and the live Computer Name lookup**

Add `import SystemConfiguration`, then implement:

```swift
static var defaultDisplayName: String {
    resolvedDefaultDisplayName(
        computerName: SCDynamicStoreCopyComputerName(nil, nil) as String?,
        hostName: ProcessInfo.processInfo.hostName
    )
}

static func resolvedDefaultDisplayName(
    computerName: String?,
    hostName: String
) -> String {
    let computerName = computerName?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let computerName, computerName.isEmpty == false { return computerName }
    let hostName = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
    return hostName.isEmpty ? "OnlySwitch Mac".localized() : hostName
}
```

Do not migrate or overwrite `UserDefaults` values; the live loader must continue to prefer a saved `displayName`.

- [ ] **Step 4: Re-run the focused test and build the Mac app**

Run the Step 2 command, then:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch \
  -configuration Release -sdk macosx build
```

Expected: the focused tests pass when the scanner permits execution; the Release build exits 0. Any scanner failure must match the approved Xcode 26.6 baseline exactly.

- [ ] **Step 5: Commit the default-name change**

```bash
rtk git add OnlySwitch/Features/RemoteAccess/Settings/RemoteAccessSettingsFeature.swift \
  OnlySwitchTests/RemoteAccess/RemoteAccessSettingsFeatureTests.swift
rtk git commit -m "fix: use Mac computer name for remote access"
```

---

### Task 4: Normalize Dashboard Tile Icon Size

**Files:**
- Modify: `OnlySwitchRemote/Features/Dashboard/ControlTileView.swift:12-92`
- Modify: `OnlySwitchRemoteTests/DashboardFeatureTests.swift`

**Interfaces:**
- Consumes: `RemoteControlIcon.systemSymbol` and `RemoteControlIcon.png`.
- Produces: `ControlTileView.iconSize == 28` and a common aspect-fit rendering path.

- [ ] **Step 1: Add a failing icon-size contract test**

Add to `DashboardFeatureTests`:

```swift
@Test func tileIconsUseFixedVisualSize() {
    #expect(ControlTileView.iconSize == 28)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -destination 'platform=iOS Simulator,id=31DCF226-CD61-4F2D-A760-E4C3ACEF1C35' \
  -only-testing:OnlySwitchRemoteTests/DashboardFeatureTests/tileIconsUseFixedVisualSize test
```

Expected: compilation fails because `ControlTileView.iconSize` does not exist.

- [ ] **Step 3: Give every icon the same visual frame**

Add:

```swift
static let iconSize: CGFloat = 28
```

Change the tile header to:

```swift
controlIcon
    .frame(width: Self.iconSize, height: Self.iconSize)
    .frame(width: 34, height: 34)
    .foregroundStyle(iconColor)
```

Remove `.font(.title2)`. Make every image branch resizable and aspect-fit:

```swift
@ViewBuilder
private var controlIcon: some View {
    switch descriptor.icon {
    case let .systemSymbol(name):
        Image(systemName: name)
            .resizable()
            .scaledToFit()
    case let .png(data):
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "switch.2")
                .resizable()
                .scaledToFit()
        }
    }
}
```

- [ ] **Step 4: Run all dashboard tests and verify GREEN**

Run the full `DashboardFeatureTests` command from Task 2 Step 4.

Expected: all dashboard tests pass.

- [ ] **Step 5: Commit the icon change**

```bash
rtk git add OnlySwitchRemote/Features/Dashboard/ControlTileView.swift \
  OnlySwitchRemoteTests/DashboardFeatureTests.swift
rtk git commit -m "fix: normalize remote tile icon size"
```

---

### Task 5: Full Verification and Physical iPhone Installation

**Files:**
- Verify only; no source changes expected.

**Interfaces:**
- Consumes: the four task commits.
- Produces: verified simulator tests, Mac/iPhone builds, and a corrected app installed on Bo’s iPhone 16 Pro.

- [ ] **Step 1: Verify source hygiene and protected user changes**

Run:

```bash
rtk git diff --check
rtk git status --short
rtk rg -n "OnlySwitchRemote diagnostic|discovery candidate:|discovery state:" OnlySwitchRemote
```

Expected: no whitespace errors or diagnostic logging. The protected project/localization files and `.superpowers/` may remain dirty but must not appear in any task commit.

- [ ] **Step 2: Run the complete iOS Remote test target**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -destination 'platform=iOS Simulator,id=31DCF226-CD61-4F2D-A760-E4C3ACEF1C35' \
  -only-testing:OnlySwitchRemoteTests test
```

Expected: exit 0 with no test failures.

- [ ] **Step 3: Run shared module tests**

Run:

```bash
cd Modules && rtk swift test
```

Expected: all Swift Testing and XCTest module tests pass.

- [ ] **Step 4: Build both applications**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch \
  -configuration Release -sdk macosx build
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -configuration Debug -destination 'id=00008140-000A395426E3001C' build
```

Expected: both builds exit 0.

- [ ] **Step 5: Install and launch the iPhone build**

Run:

```bash
rtk xcrun devicectl device install app \
  --device BD35535F-A2C7-5647-9848-90D51150B84B \
  /Users/boliu/Library/Developer/Xcode/DerivedData/OnlySwitch-cccumnkfcbuifmcwfsfmlbsstpjk/Build/Products/Debug-iphoneos/OnlySwitchRemote.app
rtk xcrun devicectl device process launch \
  --device BD35535F-A2C7-5647-9848-90D51150B84B \
  jacklandrin.OnlySwitchRemote
```

Expected: installation and launch succeed when the phone is unlocked.

- [ ] **Step 6: Perform physical acceptance checks**

On the iPhone verify:

1. The paired Mac reconnects after the pairing sheet closes without showing a false local-network error.
2. The selector remains one line and middle-truncates the long ISP hostname while VoiceOver retains the full value.
3. Opening the selector shows all paired Macs and changes selection.
4. Mute, Hide Menu Bar Icons, Autohide Dock, and Dark Mode icons occupy the same 28-point visual frame.
5. Controls become enabled after authentication and still trigger the selected Mac.

- [ ] **Step 7: Request final code review**

Use `superpowers:requesting-code-review` against the complete task diff. Address only verified findings, then repeat Steps 1-5 if any source changes are made.
