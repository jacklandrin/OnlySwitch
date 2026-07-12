# Only Control Secondary Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display each built-in switch's current secondary information on its Only Control tile, including a compact AirPods battery summary and the Only Agent model.

**Architecture:** Extend `ControlItemViewState` with an optional subtitle and centralize subtitle normalization in the OnlyControl module. The app reducer fetches `currentInfo()` during dashboard refresh and supplies the normalized value; the tile renders it accessibly while preserving the existing layout when absent.

**Tech Stack:** Swift 6.2, SwiftUI, Composable Architecture, Swift Testing, macOS 14+

## Global Constraints

- Keep the existing 85-by-85-point tile size and dashboard ordering behavior.
- Do not change switch-provider APIs or one-column mode.
- Do not add third-party dependencies.
- Do not display unavailable or empty information.

---

### Task 1: Secondary Information Model and Formatting

**Files:**
- Create: `Modules/Sources/OnlyControl/ControlItemSecondaryInformation.swift`
- Modify: `Modules/Sources/OnlyControl/ControlItemViewState.swift`
- Create: `Modules/Tests/ModulesTests/ControlItemSecondaryInformationTests.swift`

**Interfaces:**
- Produces: `ControlItemSecondaryInformation.subtitle(info:isAirPods:) -> String?`
- Produces: `ControlItemViewState.subtitle: String?`

- [ ] Write failing Swift Testing cases for empty information, ordinary text, and AirPods battery strings.
- [ ] Run `rtk swift test --package-path Modules --filter ControlItemSecondaryInformationTests` and confirm the missing formatter/state API causes failure.
- [ ] Implement the formatter and optional state property with initializer defaulting to `nil`.
- [ ] Re-run the focused tests and confirm they pass.

### Task 2: Dashboard Data Flow and Tile Presentation

**Files:**
- Modify: `OnlySwitch/Features/OnlyControl/OnlyControlReducer.swift`
- Modify: `OnlySwitch/Features/OnlyControl/OnlyControlView.swift`
- Modify: `Modules/Sources/OnlyControl/ControlItemView.swift`

**Interfaces:**
- Consumes: `ControlItemSecondaryInformation.subtitle(info:isAirPods:) -> String?`
- Consumes: `ControlItemViewState.subtitle: String?`

- [ ] Fetch `currentInfo()` for visible built-in switches during dashboard refresh and pass its normalized subtitle into the view state.
- [ ] Render nonempty subtitles below the title using secondary hierarchical styling, one-line scaling, and a combined accessibility value.
- [ ] Remove the AirPods battery display beside the clock and its now-unused reducer state/actions.
- [ ] Run the focused module tests and `rtk swift test --package-path Modules`.
- [ ] Build with `rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx build` and inspect the final diff.
