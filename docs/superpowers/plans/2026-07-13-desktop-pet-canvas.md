# Desktop Pet Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the pet's transparent drawing canvas so its horizontal glow and vertical motion fade naturally without changing the visible vector artwork size.

**Architecture:** Centralize the panel and artwork dimensions in `DesktopPetMetrics`, then let `DesktopPetView` center the unchanged artwork inside the larger canvas. Pure `DesktopPetLayout` functions compensate the default origin for transparent padding and migrate autosaved legacy frames by preserving their center.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing

## Global Constraints

- Expand the transparent canvas to exactly `152 × 160` points.
- Keep the vector artwork coordinate space exactly `120 × 130` points.
- Keep the existing vector dimensions, glow strength, animation timing, Only Control behavior, and preference behavior unchanged.
- Keep the artwork boundary 24 points from the left and bottom visible-screen edges at the default position.
- Preserve the center of an existing autosaved frame while migrating it to the expanded canvas size.
- Keep all desktop-pet code in the standalone `DesktopPet` module.

---

### Task 1: Canvas geometry and legacy-frame migration

**Files:**
- Create: `Modules/Sources/DesktopPet/DesktopPetMetrics.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetLayout.swift`
- Modify: `Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift`

**Interfaces:**
- Produces: `DesktopPetMetrics.canvasSize`, `artworkSize`, `visibleScreenInset`, and `defaultPanelInsets`.
- Produces: `DesktopPetLayout.defaultFrame(size:visibleFrame:horizontalInset:verticalInset:) -> CGRect`.
- Produces: `DesktopPetLayout.resizedFramePreservingCenter(_:to:) -> CGRect`.

- [ ] **Step 1: Write failing geometry tests**

```swift
@Test func expandedCanvasKeepsArtworkBoundaryAtRequestedInset() {
    let frame = DesktopPetLayout.defaultFrame(
        size: DesktopPetMetrics.canvasSize,
        visibleFrame: CGRect(x: 0, y: 25, width: 1_440, height: 875),
        horizontalInset: DesktopPetMetrics.defaultPanelInsets.width,
        verticalInset: DesktopPetMetrics.defaultPanelInsets.height
    )

    #expect(frame == CGRect(x: 8, y: 34, width: 152, height: 160))
    #expect(frame.minX + 16 == 24)
    #expect(frame.minY + 15 == 49)
}

@Test func resizingLegacyFramePreservesItsCenter() {
    let frame = DesktopPetLayout.resizedFramePreservingCenter(
        CGRect(x: 24, y: 49, width: 120, height: 130),
        to: DesktopPetMetrics.canvasSize
    )

    #expect(frame == CGRect(x: 8, y: 34, width: 152, height: 160))
}
```

- [ ] **Step 2: Run the focused tests and verify red**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: compilation fails because `DesktopPetMetrics`, asymmetric default insets, and `resizedFramePreservingCenter` do not exist.

- [ ] **Step 3: Add the metrics and pure geometry**

```swift
import CoreGraphics

enum DesktopPetMetrics {
    static let canvasSize = CGSize(width: 152, height: 160)
    static let artworkSize = CGSize(width: 120, height: 130)
    static let visibleScreenInset: CGFloat = 24

    static var defaultPanelInsets: CGSize {
        CGSize(
            width: visibleScreenInset - (canvasSize.width - artworkSize.width) / 2,
            height: visibleScreenInset - (canvasSize.height - artworkSize.height) / 2
        )
    }
}
```

Change `defaultFrame` to accept `horizontalInset` and `verticalInset`, then add:

```swift
public static func resizedFramePreservingCenter(_ frame: CGRect, to size: CGSize) -> CGRect {
    CGRect(
        x: frame.midX - size.width / 2,
        y: frame.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
}
```

- [ ] **Step 4: Run the focused tests and verify green**

Run: `rtk swift test --package-path Modules --filter DesktopPetLayoutTests`

Expected: all `DesktopPetLayoutTests` pass.

### Task 2: Expanded panel and centered artwork

**Files:**
- Modify: `Modules/Sources/DesktopPet/DesktopPetController.swift`
- Modify: `Modules/Sources/DesktopPet/DesktopPetView.swift`

**Interfaces:**
- Consumes: `DesktopPetMetrics.canvasSize`, `artworkSize`, and `defaultPanelInsets`.
- Consumes: `DesktopPetLayout.resizedFramePreservingCenter(_:to:)`.

- [ ] **Step 1: Expand the SwiftUI root while keeping artwork dimensions unchanged**

Wrap `DesktopPetArtwork` in its existing `120 × 130` frame and change the outer `TimelineView` frame to `152 × 160`:

```swift
DesktopPetArtwork(/* existing arguments */)
    .frame(
        width: DesktopPetMetrics.artworkSize.width,
        height: DesktopPetMetrics.artworkSize.height
    )

// After TimelineView
.frame(
    width: DesktopPetMetrics.canvasSize.width,
    height: DesktopPetMetrics.canvasSize.height
)
```

- [ ] **Step 2: Expand and migrate the AppKit panel**

Use `DesktopPetMetrics.canvasSize` when creating the panel. If `setFrameUsingName` restores an existing frame, replace it with `resizedFramePreservingCenter(restoredFrame, to: canvasSize)`. Otherwise create the default frame with the asymmetric panel insets. Constrain and save the migrated frame through the existing `show()` path.

- [ ] **Step 3: Run module tests**

Run: `rtk swift test --package-path Modules`

Expected: 22 tests pass with zero failures.

- [ ] **Step 4: Run strict-concurrency app build**

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx SWIFT_STRICT_CONCURRENCY=complete build`

Expected: exit code 0 with no new concurrency diagnostics.

### Task 3: Visual and branch verification

**Files:**
- Review all files changed in Tasks 1 and 2.

**Interfaces:**
- Produces a verified follow-up commit on `codex/desktop-pet`.

- [ ] **Step 1: Launch the Debug app from the worktree build**

Run the built OnlySwitch app and enable General → Show Desktop Pet. Verify the closed and open glows fade before the left/right panel boundaries and the legs/ground shadow do not clip while breathing or dragging.

- [ ] **Step 2: Run final automated verification**

Run: `rtk swift test --package-path Modules`

Run: `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx SWIFT_STRICT_CONCURRENCY=complete build`

Expected: both commands exit 0 and all 22 module tests pass.

- [ ] **Step 3: Commit**

```bash
rtk git add Modules/Sources/DesktopPet Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift docs/superpowers/plans/2026-07-13-desktop-pet-canvas.md
rtk git commit -m "fix: expand desktop pet canvas"
```
