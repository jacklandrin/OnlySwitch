# Desktop Pet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in, draggable, animated SwiftUI desktop pet that always opens Only Control.

**Architecture:** A new `DesktopPet` Swift Package target owns the vector mascot, transparent floating panel, gesture handling, frame persistence, and screen clamping. The OnlySwitch app owns the persisted visibility preference and injects an activation closure that raises the existing `OnlyControlWindow`.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, Swift Package Manager, macOS 14+

## Global Constraints

- The feature is an independent `DesktopPet` product and target under `Modules`.
- The module depends only on SwiftUI and AppKit; it must not import app targets, Only Control, or Composable Architecture.
- The pet is hidden by default and is controlled by a General settings toggle.
- Clicking always opens Only Control without changing the selected menu-bar appearance.
- The mascot is original SwiftUI vector artwork, approximately 110 by 120 points, with subtle animation and Reduce Motion support.
- Preserve the existing unstaged build-number change in `OnlySwitch.xcodeproj/project.pbxproj`.

---

### Task 1: Add the DesktopPet module and testable layout policy

**Files:**
- Modify: `Modules/Package.swift`
- Create: `Modules/Sources/DesktopPet/DesktopPetLayout.swift`
- Create: `Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift`

**Interfaces:**
- Produces: `DesktopPetLayout.defaultFrame(size:visibleFrame:inset:) -> CGRect`
- Produces: `DesktopPetLayout.constrainedFrame(_:to:) -> CGRect`
- Produces: `DesktopPetLayout.bestScreenIndex(for:visibleFrames:) -> Int?`
- Produces: `DesktopPetInteraction.isClick(translation:threshold:) -> Bool`

- [ ] **Step 1: Register the library and failing tests**

Add `.library(name: "DesktopPet", targets: ["DesktopPet"])`, a `.target(name: "DesktopPet")`, add `"DesktopPet"` to `ModulesTests` dependencies, and create tests equivalent to:

```swift
import CoreGraphics
import Testing
@testable import DesktopPet

struct DesktopPetLayoutTests {
    @Test func defaultFrameUsesLowerRightInset() {
        let frame = DesktopPetLayout.defaultFrame(
            size: CGSize(width: 120, height: 130),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875),
            inset: 28
        )
        #expect(frame == CGRect(x: 1292, y: 53, width: 120, height: 130))
    }

    @Test func frameIsClampedInsideVisibleFrame() {
        let result = DesktopPetLayout.constrainedFrame(
            CGRect(x: -50, y: 850, width: 120, height: 130),
            to: CGRect(x: 0, y: 25, width: 1440, height: 875)
        )
        #expect(result == CGRect(x: 0, y: 770, width: 120, height: 130))
    }

    @Test func screenWithLargestIntersectionWins() {
        let index = DesktopPetLayout.bestScreenIndex(
            for: CGRect(x: 1370, y: 100, width: 120, height: 130),
            visibleFrames: [
                CGRect(x: 0, y: 0, width: 1440, height: 900),
                CGRect(x: 1440, y: 0, width: 1920, height: 1080)
            ]
        )
        #expect(index == 1)
    }

    @Test func clickThresholdDistinguishesDrag() {
        #expect(DesktopPetInteraction.isClick(translation: .init(width: 2, height: 3)))
        #expect(!DesktopPetInteraction.isClick(translation: .init(width: 8, height: 0)))
    }
}
```

- [ ] **Step 2: Run the tests to verify failure**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: FAIL because the `DesktopPet` target or layout types do not exist.

- [ ] **Step 3: Implement the minimal pure policy**

Implement `DesktopPetLayout` with lower-right placement, min/max clamping, and largest-intersection screen selection. If every intersection is empty, select the screen whose midpoint is closest to the pet midpoint. Implement `DesktopPetInteraction.isClick` using Euclidean distance and a default four-point threshold.

```swift
public enum DesktopPetInteraction {
    public static func isClick(
        translation: CGSize,
        threshold: CGFloat = 4
    ) -> Bool {
        hypot(translation.width, translation.height) <= threshold
    }
}
```

- [ ] **Step 4: Run the focused and full package tests**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: all four DesktopPet layout tests PASS.

Run: `rtk swift test --package-path Modules`

Expected: all package tests PASS.

- [ ] **Step 5: Commit the module policy**

```bash
rtk git add Modules/Package.swift Modules/Sources/DesktopPet/DesktopPetLayout.swift Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift
rtk git commit -m "feat: add desktop pet layout module"
```

### Task 2: Build the animated SwiftUI mascot and floating panel

**Files:**
- Create: `Modules/Sources/DesktopPet/DesktopPetView.swift`
- Create: `Modules/Sources/DesktopPet/DesktopPetController.swift`

**Interfaces:**
- Produces: `public struct DesktopPetView: View`
- Produces: `@MainActor public final class DesktopPetController`
- Produces: `public init(onActivate: @escaping @MainActor () -> Void)`
- Produces: `public func show()` and `public func hide()`

- [ ] **Step 1: Add a failing compile-time API test**

Extend `DesktopPetLayoutTests.swift` with a main-actor construction test:

```swift
@Test @MainActor func controllerStartsHidden() {
    let controller = DesktopPetController(onActivate: {})
    #expect(!controller.isVisible)
}
```

- [ ] **Step 2: Run the focused test to verify failure**

Run: `rtk swift test --package-path Modules --filter controllerStartsHidden`

Expected: FAIL because `DesktopPetController` does not exist.

- [ ] **Step 3: Implement the vector mascot**

Build `DesktopPetView` from SwiftUI shapes only: a blue-violet capsule body, inset dark face, bright slider knob, two eyes, small arms and legs, highlights, and soft shadow. Drive breathing, blink, and slider offset from a paused `TimelineView`; use `@Environment(\.accessibilityReduceMotion)` to return zero motion. Expose one combined accessibility element with label `Open Only Control` and hint `Click to open Only Control. Drag to move.`

The public initializer is:

```swift
public init(isActive: Bool = true, isDragging: Bool = false)
```

The view frame is 120 by 130 points, while the visible character remains approximately 110 by 120 points.

- [ ] **Step 4: Implement the panel controller and gesture root**

Create one transparent, borderless, non-activating `NSPanel` with level `.floating`, `hidesOnDeactivate = false`, `isReleasedWhenClosed = false`, and collection behavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.

Host an internal root view with `DragGesture(minimumDistance: 0)`. On first change, capture the panel origin. During drag, update the origin from the captured origin plus translation and mark the presentation model as dragging once the four-point threshold is crossed. On end, activate only when `DesktopPetInteraction.isClick` returns true; otherwise clamp the final frame and persist it with frame autosaving name `OnlySwitchDesktopPetWindow`.

Observe `NSApplication.didChangeScreenParametersNotification` once, reclamp on notification, and remove the observer in `deinit`. `show()` restores and clamps the frame, marks animation active, and orders front. `hide()` saves the frame, pauses animation, and orders out. Expose read-only `public var isVisible: Bool`.

- [ ] **Step 5: Run module tests and build**

Run: `rtk swift test --package-path Modules --filter DesktopPet`

Expected: DesktopPet tests PASS.

Run: `rtk swift build --package-path Modules`

Expected: package build succeeds with no DesktopPet errors.

- [ ] **Step 6: Commit the view and panel**

```bash
rtk git add Modules/Sources/DesktopPet/DesktopPetView.swift Modules/Sources/DesktopPet/DesktopPetController.swift Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift
rtk git commit -m "feat: add animated desktop pet panel"
```

### Task 3: Add the hidden-by-default preference and General setting

**Files:**
- Modify: `Modules/Sources/Extensions/UserDefaultsKeys.swift`
- Modify: `Modules/Sources/Defines/NotificationNames.swift`
- Modify: `OnlySwitch/Model/Preferences.swift`
- Modify: `OnlySwitch/Features/Settings/General/GeneralVM.swift`
- Modify: `OnlySwitch/Features/Settings/General/GeneralView.swift`
- Modify: `Localization/Localizable.xcstrings`
- Modify: `OnlySwitchTests/OnlySwitchTests.swift`

**Interfaces:**
- Produces: `UserDefaults.Key.showDesktopPet`
- Produces: `Notification.Name.desktopPetVisibilityChanged`
- Produces: `Preferences.showDesktopPet: Bool`
- Produces: `GeneralVM.showDesktopPet: Bool`

- [ ] **Step 1: Write failing preference tests**

Add tests that remove the key, verify the default is false, set the preference to true, and observe that `.desktopPetVisibilityChanged` sees the new value. Restore the original stored object in `defer` so the test does not alter developer preferences.

```swift
@MainActor
func testDesktopPetIsHiddenByDefaultAndPublishesChanges() {
    let defaults = UserDefaults.standard
    let key = UserDefaults.Key.showDesktopPet
    let original = defaults.object(forKey: key)
    defer {
        if let original { defaults.set(original, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
    defaults.removeObject(forKey: key)
    XCTAssertFalse(Preferences.shared.showDesktopPet)

    var observed: Bool?
    let token = NotificationCenter.default.addObserver(
        forName: .desktopPetVisibilityChanged,
        object: nil,
        queue: .main
    ) { _ in observed = Preferences.shared.showDesktopPet }
    defer { NotificationCenter.default.removeObserver(token) }

    Preferences.shared.showDesktopPet = true
    XCTAssertEqual(observed, true)
}
```

- [ ] **Step 2: Run the app test to verify failure**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx -only-testing:OnlySwitchTests/OnlySwitchTests/testDesktopPetIsHiddenByDefaultAndPublishesChanges test`

Expected: FAIL because the key, preference, and notification do not exist.

- [ ] **Step 3: Implement the preference and binding**

Add key `showDesktopPetKey`, notification `desktopPetVisibilityChanged`, and:

```swift
@UserDefaultValue(key: UserDefaults.Key.showDesktopPet, defaultValue: false)
var showDesktopPet: Bool {
    didSet {
        NotificationCenter.default.post(
            name: .desktopPetVisibilityChanged,
            object: showDesktopPet
        )
    }
}
```

Add a read/write computed property to `GeneralVM` and a `Toggle("Show Desktop Pet".localized(), isOn: $generalVM.showDesktopPet)` in the General section. Add English, Simplified Chinese (`显示桌面宠物`), and Traditional Chinese (`顯示桌面寵物`) localizations to the string catalog.

- [ ] **Step 4: Run the focused test**

Run the same `xcodebuild` command from Step 2.

Expected: the new preference test PASS.

- [ ] **Step 5: Commit settings support**

```bash
rtk git add Modules/Sources/Extensions/UserDefaultsKeys.swift Modules/Sources/Defines/NotificationNames.swift OnlySwitch/Model/Preferences.swift OnlySwitch/Features/Settings/General/GeneralVM.swift OnlySwitch/Features/Settings/General/GeneralView.swift Localization/Localizable.xcstrings OnlySwitchTests/OnlySwitchTests.swift
rtk git commit -m "feat: add desktop pet setting"
```

### Task 4: Wire the module into OnlySwitch and verify the feature

**Files:**
- Modify: `OnlySwitch/AppDelegate.swift`
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `DesktopPetController(onActivate:)`, `show()`, `hide()`
- Consumes: `Preferences.showDesktopPet`
- Consumes: `Notification.Name.desktopPetVisibilityChanged`

- [ ] **Step 1: Add the local package product to the app target**

Add a `DesktopPet` `XCSwiftPackageProductDependency`, include it in the OnlySwitch target's `packageProductDependencies`, and add its `PBXBuildFile` to the OnlySwitch Frameworks phase. Do not alter the user's `CURRENT_PROJECT_VERSION = 258` lines.

- [ ] **Step 2: Wire one controller into AppDelegate**

Import `DesktopPet`, add retained `desktopPetController` and observer token properties, and call `setupDesktopPet()` after the existing status-bar setup.

```swift
private func setupDesktopPet() {
    let controller = DesktopPetController {
        OnlyControlWindow.shared.show()
    }
    desktopPetController = controller

    if Preferences.shared.showDesktopPet {
        controller.show()
    }

    desktopPetObserver = NotificationCenter.default.addObserver(
        forName: .desktopPetVisibilityChanged,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor [weak self] in
            guard let controller = self?.desktopPetController else { return }
            Preferences.shared.showDesktopPet ? controller.show() : controller.hide()
        }
    }
}
```

Remove the observer during app termination. The activation closure must call Only Control directly and must not route through `StatusBarController`, because that controller conditionally opens the selected menu appearance.

- [ ] **Step 3: Build and run all automated tests**

Run: `rtk swift test --package-path Modules`

Expected: all module tests PASS.

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx build`

Expected: `** BUILD SUCCEEDED **`.

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx test`

Expected: tests complete without DesktopPet or preference failures.

- [ ] **Step 4: Perform manual behavior checks**

Launch the Debug app and verify: the pet is absent by default; the General toggle shows and hides it immediately; it stays above normal windows; dragging does not open Only Control; clicking opens Only Control for every menu appearance; the position survives hide/show and relaunch; the pet remains reachable after display changes; animations stop under Reduce Motion.

- [ ] **Step 5: Review the final diff and commit integration**

Run: `rtk git diff --check`

Expected: no whitespace errors.

Verify `git diff` keeps the user's build-number change and includes only the intended DesktopPet product additions around it.

```bash
rtk git add OnlySwitch/AppDelegate.swift OnlySwitch.xcodeproj/project.pbxproj
rtk git commit -m "feat: integrate desktop pet launcher"
```
