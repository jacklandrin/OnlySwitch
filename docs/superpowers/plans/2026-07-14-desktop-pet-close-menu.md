# Desktop Pet Close Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a right-click **Close** action that persistently disables the desktop pet until the user enables it again in General settings.

**Architecture:** The DesktopPet module exposes close as an injected callback and keeps app preferences outside the module. `DesktopPetRootView` renders the SwiftUI context menu, `DesktopPetController` routes its action, and `AppDelegate` persists the result through the existing `showDesktopPet` preference and notification flow.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, macOS 14+

## Global Constraints

- The context menu contains exactly one destructive action labeled **Close**.
- Closing immediately sets `showDesktopPet` to `false` without confirmation.
- Left-click activation and drag-to-move behavior remain unchanged.
- The DesktopPet module must not depend on OnlySwitch app preferences.
- Add no third-party dependencies.

---

### Task 1: Route Close Through the DesktopPet Module

**Files:**
- Modify: `Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift:92-109`
- Modify: `Modules/Sources/DesktopPet/DesktopPetController.swift:16-40,67-91`
- Modify: `Modules/Sources/DesktopPet/DesktopPetRootView.swift:3-24`

**Interfaces:**
- Consumes: existing `DesktopPetController(onActivate:)` construction and `DesktopPetRootView` hosting setup.
- Produces: `DesktopPetController.init(onActivate:onClose:)`, internal `DesktopPetController.close()`, and `DesktopPetRootView.onClose: @MainActor () -> Void`.

- [ ] **Step 1: Write the failing controller callback test**

Add this test next to the existing controller tests:

```swift
@Test @MainActor func controllerRoutesCloseRequest() {
    var didClose = false
    let controller = DesktopPetController(
        onActivate: {},
        onClose: { didClose = true }
    )

    controller.close()

    #expect(didClose)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests/controllerRoutesCloseRequest`

Expected: compilation fails because `DesktopPetController` has no `onClose` parameter or `close()` method.

- [ ] **Step 3: Add the close callback to the controller**

Add storage, preserve source compatibility with a default callback, and provide the internal testable route:

```swift
private let onActivate: @MainActor () -> Void
private let onClose: @MainActor () -> Void

public init(
    onActivate: @escaping @MainActor () -> Void,
    onClose: @escaping @MainActor () -> Void = {}
) {
    self.onActivate = onActivate
    self.onClose = onClose
    panel = DesktopPetPanel(
        contentRect: CGRect(origin: .zero, size: DesktopPetMetrics.canvasSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    super.init()

    configurePanel()
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(screenParametersDidChange),
        name: NSApplication.didChangeScreenParametersNotification,
        object: nil
    )
}

func close() {
    onClose()
}
```

In `configurePanel()`, pass the close route to the root view alongside the existing drag closures:

```swift
onClose: { [weak self] in
    self?.close()
}
```

- [ ] **Step 4: Add the SwiftUI context menu**

Add the callback property to `DesktopPetRootView`:

```swift
let onClose: @MainActor () -> Void
```

Attach the menu to the existing shaped and gestured pet view:

```swift
.contextMenu {
    Button("Close", role: .destructive, action: onClose)
}
```

- [ ] **Step 5: Run DesktopPet tests and verify GREEN**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: all `DesktopPetLayoutTests` pass.

- [ ] **Step 6: Commit the module behavior**

Run:

```bash
rtk git add Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift Modules/Sources/DesktopPet/DesktopPetController.swift Modules/Sources/DesktopPet/DesktopPetRootView.swift
rtk git commit -m "feat: add desktop pet close menu"
```

### Task 2: Persist Close Through General Settings

**Files:**
- Modify: `OnlySwitch/AppDelegate.swift:231-253`
- Verify: `OnlySwitchTests/OnlySwitchTests.swift:87-115`

**Interfaces:**
- Consumes: `DesktopPetController.init(onActivate:onClose:)` from Task 1 and `Preferences.shared.showDesktopPet`'s existing notification behavior.
- Produces: app-level close behavior that persists `showDesktopPet = false` and hides the panel through `desktopPetVisibilityDidChange()`.

- [ ] **Step 1: Confirm the existing preference contract test passes before integration**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx -only-testing:OnlySwitchTests/OnlySwitchTests/testDesktopPetIsHiddenByDefaultAndPublishesChanges test`

Expected: `testDesktopPetIsHiddenByDefaultAndPublishesChanges` passes, proving preference writes publish the visibility notification consumed by `AppDelegate`.

- [ ] **Step 2: Supply the persistent close callback**

Replace trailing-closure construction in `setupDesktopPet()` with explicit callbacks:

```swift
let controller = DesktopPetController(
    onActivate: {
        onlyControlWindow.toggle(monitorsOutsideClicks: true)
    },
    onClose: {
        Preferences.shared.showDesktopPet = false
    }
)
```

The existing `.desktopPetVisibilityChanged` observer will receive the preference change and call `controller.hide()`.

- [ ] **Step 3: Run package tests**

Run: `rtk swift test --package-path Modules`

Expected: all module tests pass without failures.

- [ ] **Step 4: Build the app**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx build`

Expected: `BUILD SUCCEEDED` with no new compiler errors or warnings from the changed files.

- [ ] **Step 5: Inspect the final diff**

Run: `rtk git diff --check` and `rtk git diff -- Modules/Sources/DesktopPet Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift OnlySwitch/AppDelegate.swift`

Expected: no whitespace errors; the diff contains only the callback route, context-menu action, persistent preference write, and test.

- [ ] **Step 6: Commit app integration**

Run:

```bash
rtk git add OnlySwitch/AppDelegate.swift
rtk git commit -m "feat: persist desktop pet close action"
```
