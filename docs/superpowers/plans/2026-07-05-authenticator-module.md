# Authenticator Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Authenticator feature into the existing `Modules` SwiftPM package while leaving `AuthenticatorSwitch` in the app target.

**Architecture:** Add a new `Authenticator` SwiftPM target that owns Authenticator models, import parsing, TOTP logic, store, and SwiftUI feature views. The app target links the package product and keeps only app-specific switch glue.

**Tech Stack:** Swift 6.2, SwiftPM, SwiftUI, CryptoKit, Swift Testing, Xcode project package products.

---

## File Structure

- Create: `Modules/Sources/Authenticator/AuthenticatorModels.swift`
- Create: `Modules/Sources/Authenticator/Base32.swift`
- Create: `Modules/Sources/Authenticator/ProtoReader.swift`
- Create: `Modules/Sources/Authenticator/TOTP.swift`
- Create: `Modules/Sources/Authenticator/OtpAuthImport.swift`
- Create: `Modules/Sources/Authenticator/AuthenticatorStore.swift`
- Create: `Modules/Sources/Authenticator/AuthenticatorImportSheet.swift`
- Create: `Modules/Sources/Authenticator/AuthenticatorSettingsView.swift`
- Create: `Modules/Sources/Authenticator/AuthenticatorPanelView.swift`
- Create: `Modules/Tests/ModulesTests/AuthenticatorTests.swift`
- Modify: `Modules/Package.swift`
- Modify: `OnlySwitch/EverySwitch/AuthenticatorSwitch.swift`
- Modify: `OnlySwitch/Features/OnlySwitchList/OnlySwitchListView.swift`
- Modify: `OnlySwitch/Features/Settings/SettingsView/SettingsView.swift`
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`
- Remove from app target/source tree: old Authenticator files under `OnlySwitch/Features/Authenticator` and `OnlySwitch/Features/Settings/Authenticator`

### Task 1: Add Failing Authenticator Module Tests

**Files:**
- Create: `Modules/Tests/ModulesTests/AuthenticatorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Authenticator

struct AuthenticatorTests {
    @Test func totpGeneratesRFC6238SHA1Code() throws {
        let secret = Data("12345678901234567890".utf8)
        let date = Date(timeIntervalSince1970: 59)

        let result = try #require(TOTP.code(
            secret: secret,
            digits: 8,
            period: 30,
            algorithm: .sha1,
            date: date
        ))

        #expect(result.code == "94287082")
        #expect(result.remaining == 1)
    }

    @Test func otpAuthURLParsesImportedToken() throws {
        let tokens = try OtpAuthImport.parse(
            input: "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=6&period=30&algorithm=SHA1"
        )

        let token = try #require(tokens.first)
        #expect(tokens.count == 1)
        #expect(token.issuer == "Example")
        #expect(token.name == "alice@example.com")
        #expect(token.secret == Data([72, 101, 108, 108, 111, 33, 222, 173, 190, 239]))
        #expect(token.digits == 6)
        #expect(token.period == 30)
        #expect(token.algorithm == .sha1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Modules && rtk swift test --filter AuthenticatorTests`

Expected: FAIL because the `Authenticator` module does not exist yet.

### Task 2: Create the Authenticator SwiftPM Target

**Files:**
- Modify: `Modules/Package.swift`
- Create files under: `Modules/Sources/Authenticator`

- [ ] **Step 1: Update Package.swift**

Add the library product:

```swift
.library(
    name: "Authenticator",
    targets: ["Authenticator"]
)
```

Add the target:

```swift
.target(
    name: "Authenticator",
    dependencies: [
        "Defines",
        "Extensions",
        "Utilities"
    ]
)
```

Add `"Authenticator"` to `ModulesTests` dependencies.

- [ ] **Step 2: Move Authenticator source files into the target**

Move the approved files from `OnlySwitch/Features/Authenticator` and `OnlySwitch/Features/Settings/Authenticator` into `Modules/Sources/Authenticator`.

- [ ] **Step 3: Expose required API**

Mark app-facing declarations public:

```swift
public enum AuthenticatorAlgorithm: String, Codable, Sendable, CaseIterable
public struct AuthenticatorAccount: Identifiable, Codable, Equatable, Sendable
@MainActor public final class AuthenticatorStore: ObservableObject
public struct AuthenticatorPanelView: View
public struct AuthenticatorSettingsView: View
```

Also expose required methods/properties such as `AuthenticatorStore.shared`, `enabled`, `accounts`, `importFromScanResult(_:)`, `deleteAccount(_:)`, `deleteAll()`, `secret(for:)`, and public view initializers.

- [ ] **Step 4: Run module tests**

Run: `cd Modules && rtk swift test --filter AuthenticatorTests`

Expected: PASS for the Authenticator tests.

### Task 3: Link the Module Into the App Target

**Files:**
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`
- Modify: `OnlySwitch/EverySwitch/AuthenticatorSwitch.swift`
- Modify: `OnlySwitch/Features/OnlySwitchList/OnlySwitchListView.swift`
- Modify: `OnlySwitch/Features/Settings/SettingsView/SettingsView.swift`

- [ ] **Step 1: Add Authenticator product to the app target**

In `project.pbxproj`, add an `XCSwiftPackageProductDependency` for product name `Authenticator`, add its build file to `Frameworks`, and add it to the app target `packageProductDependencies`.

- [ ] **Step 2: Import Authenticator in app consumers**

Add:

```swift
import Authenticator
```

to the app files that reference `AuthenticatorStore`, `AuthenticatorPanelView`, or `AuthenticatorSettingsView`.

- [ ] **Step 3: Remove old app target source entries**

Remove the moved Authenticator files from the app target `Sources` build phase and file/group references. Keep `AuthenticatorSwitch.swift` in the app target.

- [ ] **Step 4: Build the app**

Run: `xcodebuild -project /Users/boliu/Developer/OnlySwitch/OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx build`

Expected: exit 0.

### Task 4: Final Verification

**Files:**
- Inspect all modified files and stale references.

- [ ] **Step 1: Run SwiftPM tests**

Run: `cd Modules && rtk swift test`

Expected: exit 0.

- [ ] **Step 2: Run app build**

Run: `xcodebuild -project /Users/boliu/Developer/OnlySwitch/OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx build`

Expected: exit 0.

- [ ] **Step 3: Check for stale app Authenticator source references**

Run: `rtk rg -n "Features/Authenticator|Features/Settings/Authenticator|AuthenticatorModels.swift in Sources|AuthenticatorStore.swift in Sources|AuthenticatorPanelView.swift in Sources|AuthenticatorSettingsView.swift in Sources" OnlySwitch.xcodeproj/project.pbxproj`

Expected: no stale moved-source references.
