# iPhone Landscape Dashboard Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show three or four dashboard tiles per row on iPhone landscape while preserving two portrait columns and the existing regular-width adaptive layout.

**Architecture:** Add a small, testable grid strategy inside `DashboardView` that maps SwiftUI horizontal and vertical size classes to fixed or adaptive columns. Vertical compactness takes precedence so iPhone landscape uses a 180-point adaptive minimum without orientation notifications or device checks.

**Tech Stack:** Swift 6.2, SwiftUI, The Composable Architecture, Swift Testing, Xcode 26.6, iOS/iPadOS 18+.

## Global Constraints

- Support iOS and iPadOS 18 or later.
- Keep iPhone portrait at exactly two columns.
- Use adaptive columns with a 180-point minimum when vertical size class is compact.
- Preserve the existing 160-point adaptive minimum for regular-width layouts.
- Preserve 12-point grid spacing.
- Do not change tile height, padding, fonts, icons, actions, statuses, or accessibility content.
- Do not add third-party dependencies or orientation notifications.
- Do not stage `OnlySwitch.xcodeproj/project.pbxproj`, `OnlySwitchRemote/Localizable.xcstrings`, or `.superpowers/`; they contain user-owned changes.

---

### Task 1: Add the Responsive Dashboard Grid Strategy

**Files:**
- Modify: `OnlySwitchRemote/Features/Dashboard/DashboardView.swift:4-83`
- Modify: `OnlySwitchRemoteTests/DashboardFeatureTests.swift`

**Interfaces:**
- Consumes: SwiftUI `UserInterfaceSizeClass?` values from horizontal and vertical environments.
- Produces: `DashboardView.GridStrategy`, `DashboardView.gridStrategy(horizontal:vertical:)`, and its `[GridItem]` conversion.

- [ ] **Step 1: Write failing size-class strategy tests**

Add `import SwiftUI` to `DashboardFeatureTests.swift`, then add:

```swift
@Test func compactWidthPortraitKeepsTwoColumns() {
    #expect(DashboardView.gridStrategy(
        horizontal: .compact,
        vertical: .regular
    ) == .fixed(count: 2))
}

@Test func compactHeightUsesDenserLandscapeGrid() {
    #expect(DashboardView.gridStrategy(
        horizontal: .compact,
        vertical: .compact
    ) == .adaptive(minimum: 180))
    #expect(DashboardView.gridStrategy(
        horizontal: .regular,
        vertical: .compact
    ) == .adaptive(minimum: 180))
}

@Test func regularLayoutPreservesExistingAdaptiveMinimum() {
    #expect(DashboardView.gridStrategy(
        horizontal: .regular,
        vertical: .regular
    ) == .adaptive(minimum: 160))
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -destination 'platform=iOS Simulator,id=31DCF226-CD61-4F2D-A760-E4C3ACEF1C35' \
  -only-testing:OnlySwitchRemoteTests/DashboardFeatureTests test
```

Expected: compilation fails because `DashboardView.gridStrategy` and `GridStrategy` do not exist.

- [ ] **Step 3: Implement the minimum responsive strategy**

Read the vertical size class beside the existing horizontal value:

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
@Environment(\.verticalSizeClass) private var verticalSizeClass
```

Add the testable strategy:

```swift
enum GridStrategy: Equatable {
    case fixed(count: Int)
    case adaptive(minimum: CGFloat)

    var columns: [GridItem] {
        switch self {
        case let .fixed(count):
            Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
        case let .adaptive(minimum):
            [GridItem(.adaptive(minimum: minimum), spacing: 12)]
        }
    }
}

static func gridStrategy(
    horizontal: UserInterfaceSizeClass?,
    vertical: UserInterfaceSizeClass?
) -> GridStrategy {
    if vertical == .compact { return .adaptive(minimum: 180) }
    if horizontal == .compact { return .fixed(count: 2) }
    return .adaptive(minimum: 160)
}
```

Replace the existing `columns` implementation with:

```swift
private var columns: [GridItem] {
    Self.gridStrategy(
        horizontal: horizontalSizeClass,
        vertical: verticalSizeClass
    ).columns
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command.

Expected: all `DashboardFeatureTests` pass, including the three new strategy tests.

- [ ] **Step 5: Run the complete iOS Remote test target**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -destination 'platform=iOS Simulator,id=31DCF226-CD61-4F2D-A760-E4C3ACEF1C35' \
  -only-testing:OnlySwitchRemoteTests test
```

Expected: exit 0 with no test failures.

- [ ] **Step 6: Commit only the grid implementation and tests**

```bash
rtk git add OnlySwitchRemote/Features/Dashboard/DashboardView.swift \
  OnlySwitchRemoteTests/DashboardFeatureTests.swift
rtk git commit -m "feat: adapt dashboard grid for iPhone landscape"
```

---

### Task 2: Build, Install, and Verify the Landscape Layout

**Files:**
- Verify only; no source changes expected.

**Interfaces:**
- Consumes: Task 1 commit.
- Produces: verified iPhone/iPad compilation and an updated app installed on Bo’s iPhone 16 Pro.

- [ ] **Step 1: Verify source hygiene**

Run:

```bash
rtk git diff --check
rtk git status --short
```

Expected: no whitespace errors. Protected user-owned files remain unstaged and uncommitted.

- [ ] **Step 2: Build iPhone and iPad destinations**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -configuration Debug -destination 'id=00008140-000A395426E3001C' build
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=31DCF226-CD61-4F2D-A760-E4C3ACEF1C35' build
```

Expected: both builds exit 0.

- [ ] **Step 3: Install and launch the updated iPhone app**

Run:

```bash
rtk xcrun devicectl device install app \
  --device BD35535F-A2C7-5647-9848-90D51150B84B \
  /Users/boliu/Library/Developer/Xcode/DerivedData/OnlySwitch-cccumnkfcbuifmcwfsfmlbsstpjk/Build/Products/Debug-iphoneos/OnlySwitchRemote.app
rtk xcrun devicectl device process launch \
  --device BD35535F-A2C7-5647-9848-90D51150B84B \
  jacklandrin.OnlySwitchRemote
```

Expected: installation and launch succeed when the iPhone is unlocked.

- [ ] **Step 4: Perform physical acceptance checks**

On the iPhone verify:

1. Portrait shows exactly two tiles per row.
2. Rotating to landscape shows three or four tiles per row, depending on usable width.
3. Rotating back restores two columns without stale layout.
4. Titles, secondary information, unavailable explanations, icons, and status accessories are not clipped.
5. Tiles remain tappable and VoiceOver labels remain unchanged.

- [ ] **Step 5: Request final whole-change code review**

Use `superpowers:requesting-code-review` for the design, plan, implementation, and tests. Address all verified findings and repeat affected tests/builds after any source change.
