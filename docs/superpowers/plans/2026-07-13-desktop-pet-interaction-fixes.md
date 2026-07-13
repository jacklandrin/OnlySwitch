# Desktop Pet Interaction Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the desktop pet reliably toggle and reflect Only Control, drag without flutter, and start 24 points from the lower-left screen edges.

**Architecture:** Keep screen geometry and drag calculations as pure functions in the `DesktopPet` module, while the controller reads stable AppKit screen mouse coordinates. `OnlyControlWindow` remains the source of truth for presentation and reports visibility to `AppDelegate`, which mirrors it into the pet's observable presentation state.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, Swift Testing

## Global Constraints

- Keep the feature in the standalone `Modules/Sources/DesktopPet` module.
- Keep the pet always on top and draggable across Spaces.
- Clicking the pet must show only Only Control and toggle it closed on the next click.
- Clicking outside Only Control must dismiss it.
- Respect Reduce Motion and distinguish open/closed state by geometry as well as color.
- Preserve saved user positions; use a 24-point lower-left inset only when no valid saved frame exists.

---

### Task 1: Stable layout and drag geometry

**Files:**
- Modify: `Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetLayout.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetController.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetRootView.swift`

**Interfaces:**
- Produces: `DesktopPetLayout.defaultFrame(size:visibleFrame:inset:)` with lower-left placement.
- Produces: `DesktopPetInteraction.draggedOrigin(startOrigin:startMouseLocation:currentMouseLocation:) -> CGPoint`.
- Consumes: `NSEvent.mouseLocation` as a stable screen coordinate during window movement.

- [ ] **Step 1: Write failing geometry tests**

```swift
@Test func defaultFrameUsesLowerLeftInset() {
    let frame = DesktopPetLayout.defaultFrame(
        size: CGSize(width: 120, height: 130),
        visibleFrame: CGRect(x: 0, y: 25, width: 1_440, height: 875),
        inset: 24
    )
    #expect(frame == CGRect(x: 24, y: 49, width: 120, height: 130))
}

@Test func draggedOriginUsesStableScreenMouseDelta() {
    let origin = DesktopPetInteraction.draggedOrigin(
        startOrigin: CGPoint(x: 24, y: 49),
        startMouseLocation: CGPoint(x: 70, y: 100),
        currentMouseLocation: CGPoint(x: 100, y: 120)
    )
    #expect(origin == CGPoint(x: 54, y: 69))
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: FAIL because the default remains lower-right and `draggedOrigin` is absent.

- [ ] **Step 3: Implement lower-left placement and screen-coordinate drag math**

```swift
public static func draggedOrigin(
    startOrigin: CGPoint,
    startMouseLocation: CGPoint,
    currentMouseLocation: CGPoint
) -> CGPoint {
    CGPoint(
        x: startOrigin.x + currentMouseLocation.x - startMouseLocation.x,
        y: startOrigin.y + currentMouseLocation.y - startMouseLocation.y
    )
}
```

Capture `NSEvent.mouseLocation` and the panel origin once when dragging starts, then update the panel using this helper. Keep SwiftUI translation only for the click-versus-drag threshold.

- [ ] **Step 4: Run the focused test and confirm it passes**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: PASS.

### Task 2: Open and closed pet presentation

**Files:**
- Modify: `Modules/Sources/DesktopPet/DesktopPetPresentation.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetController.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetRootView.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetView.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetArtwork.swift`

**Interfaces:**
- Produces: `DesktopPetController.setControlPresented(_:)`.
- Produces: `DesktopPetView(isActive:isDragging:isControlPresented:)`.

- [ ] **Step 1: Add a controller state test**

```swift
@Test @MainActor func controllerTracksControlPresentation() {
    let controller = DesktopPetController(onActivate: {})
    controller.setControlPresented(true)
    #expect(controller.isControlPresented)
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: FAIL because the presentation API does not exist.

- [ ] **Step 3: Add observable state and vector appearance changes**

Add `isControlPresented` to `DesktopPetPresentation`, expose it read-only from the controller, and animate the face switch knob between left and right. In the open state use brighter cyan/green illumination, an illuminated status mark, and open eyes; in the closed state keep the blue, left-positioned switch. Use `.animation(_:value:)` and disable the state transition animation when Reduce Motion is enabled.

- [ ] **Step 4: Run the focused test and confirm it passes**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: PASS.

### Task 3: Only Control toggle and outside dismissal

**Files:**
- Modify: `OnlySwitch/Features/OnlyControl/OnlyControlView.swift`
- Modify: `OnlySwitch/AppDelegate.swift`

**Interfaces:**
- Produces: `OnlyControlWindow.toggle()`.
- Produces: `OnlyControlWindow.onVisibilityChanged: (@MainActor (Bool) -> Void)?`.
- Consumes: `DesktopPetController.setControlPresented(_:)`.

- [ ] **Step 1: Make window visibility transitions immediate and cancellable**

Store a `Task<Void, Never>?` for the 510 ms close animation. `show()` cancels any pending close, sets `isShowing = true`, and reports `true`. `hide()` immediately sets `isShowing = false` and reports `false`, then closes after `Task.sleep(for: .milliseconds(510))` unless cancelled.

- [ ] **Step 2: Add toggle and outside-click behavior**

```swift
func toggle() {
    isShowing ? hide() : show()
}

func windowDidResignKey(_ notification: Notification) {
    guard isShowing else { return }
    hide()
}
```

- [ ] **Step 3: Synchronize the pet from AppDelegate**

Construct the pet with `OnlyControlWindow.shared.toggle()`, assign the window visibility callback to call `controller.setControlPresented(isPresented)`, and clear the callback during app termination.

- [ ] **Step 4: Build with strict concurrency**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx SWIFT_STRICT_CONCURRENCY=complete build`

Expected: `** BUILD SUCCEEDED **` with no new concurrency diagnostics.

### Task 4: Full verification and review

**Files:**
- Review all files modified by Tasks 1–3.

**Interfaces:**
- Consumes all interfaces above.
- Produces a verified feature commit.

- [ ] **Step 1: Run all module tests**

Run: `rtk swift test --package-path Modules`

Expected: all tests pass.

- [ ] **Step 2: Run the app build**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Review accessibility, animation, and concurrency**

Confirm Reduce Motion is respected, open/closed state differs by geometry and not only color, the stored delayed-close task is cancelled before replacement and at teardown, and all UI state remains `@MainActor` isolated.

- [ ] **Step 4: Commit the fix**

```bash
rtk git add Modules/Sources/DesktopPet Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift OnlySwitch/AppDelegate.swift OnlySwitch/Features/OnlyControl/OnlyControlView.swift docs/superpowers/plans/2026-07-13-desktop-pet-interaction-fixes.md
rtk git commit -m "fix: refine desktop pet interactions"
```
