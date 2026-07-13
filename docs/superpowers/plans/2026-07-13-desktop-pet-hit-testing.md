# Desktop Pet Hit-Testing Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore reliable pet clicking and dragging while keeping the expanded glow padding non-interactive.

**Architecture:** Replace the fully transparent gesture sibling with a dedicated SwiftUI `Shape` that describes the original centered `120 × 130` interaction area. Attach the existing gesture directly to the rendered `DesktopPetView`, returning to the event path that worked before the canvas expansion.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing

## Global Constraints

- Keep the rendering canvas exactly `152 × 160` points.
- Keep the interaction rectangle exactly `120 × 130` points, centered at `(16, 15)` inside the canvas.
- Keep the transparent glow padding non-interactive.
- Do not alter artwork, shadows, animation, window geometry, Only Control behavior, or drag calculations.
- Keep the fix inside the standalone `DesktopPet` module.

---

### Task 1: Restore the rendered-view gesture path

**Files:**
- Create: `Modules/Sources/DesktopPet/DesktopPetInteractionShape.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetRootView.swift`
- Modify: `Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift`

**Interfaces:**
- Produces: `DesktopPetInteractionShape(size: CGSize)` conforming to `Shape`.
- Consumes: `DesktopPetMetrics.artworkSize` and the existing drag callbacks.

- [ ] **Step 1: Write the failing interaction-shape test**

```swift
@Test func interactionShapeMatchesOriginalPetBounds() {
    let shape = DesktopPetInteractionShape(size: DesktopPetMetrics.artworkSize)
    let bounds = shape.path(
        in: CGRect(origin: .zero, size: DesktopPetMetrics.canvasSize)
    ).boundingRect

    #expect(bounds == CGRect(x: 16, y: 15, width: 120, height: 130))
}
```

- [ ] **Step 2: Run the focused tests and verify red**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: compilation fails because `DesktopPetInteractionShape` does not exist.

- [ ] **Step 3: Implement the interaction shape**

```swift
import SwiftUI

struct DesktopPetInteractionShape: Shape {
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        Path(
            CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        )
    }
}
```

- [ ] **Step 4: Restore the gesture to `DesktopPetView`**

Replace the `ZStack`, `.allowsHitTesting(false)`, and `Color.clear` gesture layer with:

```swift
DesktopPetView(
    isActive: presentation.isActive,
    isDragging: presentation.isDragging,
    isControlPresented: presentation.isControlPresented
)
.contentShape(
    .interaction,
    DesktopPetInteractionShape(size: DesktopPetMetrics.artworkSize)
)
.gesture(
    DragGesture(minimumDistance: 0, coordinateSpace: .global)
        .onChanged(onDragChanged)
        .onEnded(onDragEnded)
)
```

- [ ] **Step 5: Run the focused tests and verify green**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: all 12 `DesktopPetLayoutTests` pass.

- [ ] **Step 6: Run complete automated verification**

Run: `rtk swift test --package-path Modules`

Expected: all 23 module tests pass (20 Swift Testing and 3 XCTest).

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx SWIFT_STRICT_CONCURRENCY=complete build`

Expected: exit code 0 with no new diagnostics.

- [ ] **Step 7: Verify the interaction in the Debug app**

Launch the worktree Debug app. Drag from the visible pet and confirm the panel moves; click the pet and confirm Only Control toggles; click the outer glow padding and confirm it does not toggle or drag.

- [ ] **Step 8: Commit**

```bash
rtk git add Modules/Sources/DesktopPet/DesktopPetInteractionShape.swift Modules/Sources/DesktopPet/DesktopPetRootView.swift Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift docs/superpowers/plans/2026-07-13-desktop-pet-hit-testing.md
rtk git commit -m "fix: restore desktop pet dragging"
```
