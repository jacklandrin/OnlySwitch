# Built-In Switch Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the Customize settings page to Built-In and make its switch catalogue searchable and grouped by related functions in the app's selected language.

**Architecture:** Preserve all visibility persistence and system effects in `CustomizeItem` and `SwitchManager`. Add a pure catalogue type that owns section membership and localized query matching; the SwiftUI view only renders filtered sections and sends existing bindings. Do not change menu-bar grouping or remote/widget contracts.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Switches and Utilities modules, XCTest, String Catalog localization.

## Global Constraints

- Preserve `SwitchType.allCases` ordering inside each Built-In category and show every current type exactly once.
- Do not alter the four-visible-switch minimum, visibility persistence, keyboard shortcuts, system effects, widgets, remote protocol, or menu-bar categories.
- Keep filtering out of the SwiftUI view, synchronous, and free of side effects.
- Search the currently localized title with Unicode-aware case- and diacritic-insensitive containment; use the source title only as fallback.
- Translate every new visible key in every existing localization catalog language. Do not alter the existing language-support list.
- Localize and expose accessible labels for search, category headings, toggles, controls, and empty state.

---

## File Structure

- Create `OnlySwitch/Features/Settings/Customize/BuiltInSwitchCatalog.swift`: deterministic categories and filtering.
- Modify `OnlySwitch/Features/Settings/Customize/CustomizeView.swift`: search field, sections, empty state, accessibility.
- Modify `OnlySwitch/Features/Settings/SettingsView/SettingsVM.swift`: add a user-facing title key while preserving the `Customize` enum identity and raw value.
- Modify `OnlySwitch/Features/Settings/SettingsView/SettingsView.swift`: use the title key in sidebar and detail navigation titles.
- Modify `Localization/Localizable.xcstrings`: all new display strings.
- Modify `OnlySwitch.xcodeproj/project.pbxproj`: app/test target file references and build phases.
- Create `OnlySwitchTests/BuiltInSwitchCatalogTests.swift`: catalogue and display-name regression coverage.

### Task 1: Implement and Test the Pure Catalogue

**Files:**
- Create: `OnlySwitch/Features/Settings/Customize/BuiltInSwitchCatalog.swift`
- Create: `OnlySwitchTests/BuiltInSwitchCatalogTests.swift`
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SwitchType`, `CustomizeItem.type`, `CustomizeItem.barInfo.title`, and `String.localized()`.
- Produces: `BuiltInSwitchSection: CaseIterable, Identifiable`; `BuiltInSwitchCatalog.sectioned(types:)`, `BuiltInSwitchCatalog.sections(items:matching:)`, and `BuiltInSwitchCatalog.matches(_:query:)`.

- [ ] **Step 1: Write failing category membership and ordering tests.**

```swift
func testSectionsContainEverySwitchExactlyOnceInAllCasesOrder() {
    let grouped = BuiltInSwitchCatalog.sectioned(types: SwitchType.allCases)
    #expect(grouped.flatMap(\.types) == SwitchType.allCases)
    #expect(Set(grouped.flatMap(\.types)).count == SwitchType.allCases.count)
}

func testAudioSectionContainsAudioControls() throws {
    let audio = try #require(
        BuiltInSwitchCatalog.sectioned(types: SwitchType.allCases)
            .first(where: { $0.section == .audio })
    )
    #expect(audio.types.contains(.mute))
    #expect(audio.types.contains(.soundMixer))
}
```

- [ ] **Step 2: Verify those tests fail.**

Run: `xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -only-testing:OnlySwitchTests/BuiltInSwitchCatalogTests test`

Expected: unresolved catalogue symbols.

- [ ] **Step 3: Add explicit, exhaustive groups.**

```swift
enum BuiltInSwitchSection: CaseIterable, Identifiable {
    case audio, displayAndAppearance, desktopAndFinder
    case cleanupAndStorage, productivityAndTools, other

    var id: Self { self }
    var titleKey: String { /* one localized key per case */ }
    func contains(_ type: SwitchType) -> Bool { /* explicit membership */ }
}

enum BuiltInSwitchCatalog {
    static func sectioned(types: [SwitchType])
      -> [(section: BuiltInSwitchSection, types: [SwitchType])] {
        BuiltInSwitchSection.allCases.compactMap { section in
            let types = types.filter(section.contains)
            return types.isEmpty ? nil : (section, types)
        }
    }
}
```

Audio includes mute, microphone mute, AirPods, radio, Spotify, Apple Music, background noise, and mixer. Place each remaining present `SwitchType` in exactly one related group; use `.other` for future values rather than omitting them.

- [ ] **Step 4: Write failing local-language and fallback-search tests.**

```swift
func testLocalizedQueryMatchesLocalizedTitle() {
    let item = makeItem(type: .darkMode, title: "深色模式")
    #expect(BuiltInSwitchCatalog.matches(item, query: "深色"))
}

func testQueryFallsBackToSourceTitle() {
    let item = makeItem(type: .darkMode, title: "深色模式")
    #expect(BuiltInSwitchCatalog.matches(item, query: "dark"))
}

func testWhitespaceQueryMatchesEveryItem() {
    #expect(BuiltInSwitchCatalog.matches(makeItem(type: .mute, title: "Mute"), query: "  "))
}
```

- [ ] **Step 5: Implement locale-aware, side-effect-free matching.**

```swift
static func matches(_ item: CustomizeItem, query: String) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return true }
    return [item.barInfo.title.localized(), item.barInfo.title].contains {
        $0.range(of: needle,
                 options: [.caseInsensitive, .diacriticInsensitive],
                 locale: .current) != nil
    }
}
```

No filter operation may assign `toggle`, call `doSwitch()`, or initialize player/system work.

- [ ] **Step 6: Make all catalogue tests pass, then commit.**

Run: `xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -only-testing:OnlySwitchTests/BuiltInSwitchCatalogTests test`

Expected: PASS.

```bash
git add OnlySwitch/Features/Settings/Customize/BuiltInSwitchCatalog.swift OnlySwitchTests/BuiltInSwitchCatalogTests.swift OnlySwitch.xcodeproj/project.pbxproj
git commit -m "feat: add built-in switch catalog"
```

### Task 2: Render Searchable and Accessible Sections

**Files:**
- Modify: `OnlySwitch/Features/Settings/Customize/CustomizeView.swift`
- Modify: `OnlySwitchTests/BuiltInSwitchCatalogTests.swift`

**Interfaces:**
- Consumes: `BuiltInSwitchCatalog.sections(items:matching:)`, `BuiltInSwitchSection.titleKey`, `CustomizeVM.allSwitches`, and `LanguageManager.currentLang`.
- Produces: a search field, non-empty functional sections, a localized empty state, and accessible controls while retaining row behavior.

- [ ] **Step 1: Add the failing empty-result test.**

```swift
func testSectionsOmitEmptyGroupsForUnmatchedQuery() {
    #expect(BuiltInSwitchCatalog.sections(items: makeItems(), matching: "not-a-switch").isEmpty)
}
```

- [ ] **Step 2: Run the focused test to confirm it fails, then add the filtering entry point.**

```swift
static func sections(items: [CustomizeItem], matching query: String)
  -> [(section: BuiltInSwitchSection, items: [CustomizeItem])] {
    BuiltInSwitchSection.allCases.compactMap { section in
        let matching = items.filter { section.contains($0.type) && matches($0, query: query) }
        return matching.isEmpty ? nil : (section, matching)
    }
}
```

Run: `xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -only-testing:OnlySwitchTests/BuiltInSwitchCatalogTests test`

Expected: PASS.

- [ ] **Step 3: Add query state and render it in the existing scroll view.**

```swift
@State private var searchText = ""

private var sections: [(section: BuiltInSwitchSection, items: [CustomizeItem])] {
    BuiltInSwitchCatalog.sections(items: customizeVM.allSwitches, matching: searchText)
}

TextField("Search Built-In Switches".localized(), text: $searchText)
    .textFieldStyle(.roundedBorder)
    .accessibilityLabel("Search Built-In Switches".localized())

ForEach(sections, id: \.section.id) { section in
    Section(section.section.titleKey.localized()) {
        ForEach(section.items, id: \.type) {
            CustomizeRowView(item: $0, currentLang: langManager.currentLang)
        }
    }
}
```

Use `LazyVStack(alignment: .leading)`. When no section remains, display `Text("No Built-In Switches Found".localized())`; never hide the field. Keep reading `langManager.currentLang` so language changes recompute display names and matches while retaining typed text.

- [ ] **Step 4: Give each existing row a meaningful accessible name.**

```swift
Toggle(item.barInfo.title.localized(), isOn: $item.toggle)
    .labelsHidden()
    .accessibilityLabel(item.barInfo.title.localized())
```

Give section titles header traits. Preserve the keyboard shortcut recorder locale injection, visibility binding, toast, and extra settings behavior. Give extra enable/disable buttons labels that include the current switch name.

- [ ] **Step 5: Build and manually verify non-destructive behavior.**

Run: `xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx build`

Expected: BUILD SUCCEEDED.

Open Built-In settings; filter, toggle an item, clear the filter, and confirm visibility remains changed. Attempt the fifth-to-last visible item through a result and confirm the existing error toast restores it. Change language with a query present and confirm headings, row titles, placeholder, empty state, and filtered results refresh without player/system side effects.

- [ ] **Step 6: Commit view integration.**

```bash
git add OnlySwitch/Features/Settings/Customize/CustomizeView.swift OnlySwitchTests/BuiltInSwitchCatalogTests.swift
git commit -m "feat: group and search built-in switches"
```

### Task 3: Rename and Translate the Settings Entry

**Files:**
- Modify: `OnlySwitch/Features/Settings/SettingsView/SettingsVM.swift`
- Modify: `OnlySwitch/Features/Settings/SettingsView/SettingsView.swift`
- Modify: `Localization/Localizable.xcstrings`
- Modify: `OnlySwitchTests/BuiltInSwitchCatalogTests.swift`

**Interfaces:**
- Consumes: existing `SettingsItem.Customize` routing in `SettingsView`.
- Produces: a Built-In display label without changing selection routing.

- [ ] **Step 1: Add the failing display-name regression test.**

```swift
func testCustomizeSettingsCaseKeepsItsIdentifierAndDisplaysBuiltIn() {
    #expect(SettingsItem.Customize.rawValue == "Customize")
    #expect(SettingsItem.Customize.titleLocalizationKey == "Built-In")
}
```

- [ ] **Step 2: Add a dedicated display-title key and use it in navigation.**

```swift
var titleLocalizationKey: String {
    switch self {
    case .Customize: "Built-In"
    default: rawValue
    }
}
```

Replace each settings sidebar/detail use of `item.rawValue.localized()` with `item.titleLocalizationKey.localized()`. Do not rename the enum case or change its raw value: `Customize` is a deep-link-compatible internal identifier and is used by settings routing.

- [ ] **Step 3: Translate all new catalog keys.**

Add `Built-In`, `Search Built-In Switches`, `No Built-In Switches Found`, and the chosen section-title keys to `Localization/Localizable.xcstrings`. Supply a non-empty translation in every existing catalog localization. Retain `Customize` until no shipped source reference remains.

- [ ] **Step 4: Verify localization, focused tests, full tests, and build.**

Run: `plutil -lint Localization/Localizable.xcstrings`

Expected: `Localization/Localizable.xcstrings: OK`.

Run: `xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' -only-testing:OnlySwitchTests/BuiltInSwitchCatalogTests test`

Expected: PASS.

Run: `xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -destination 'platform=macOS' test`

Expected: PASS, or separately report existing unrelated failures.

Run: `xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit the rename and translations.**

```bash
git add OnlySwitch/Features/Settings/SettingsView/SettingsVM.swift OnlySwitch/Features/Settings/SettingsView/SettingsView.swift Localization/Localizable.xcstrings OnlySwitchTests/BuiltInSwitchCatalogTests.swift
git commit -m "feat: rename customize settings to built-in"
```

## Self-Review

Spec coverage: Task 3 renames the entry and localizes its label. Task 1 provides exhaustive, stable functional groups plus current-language matching with source-title fallback. Task 2 provides search, empty state, language refresh, accessibility, and protection of existing persistence/effects. No task changes the menu-bar, widget, remote, permission, or system-effect boundary.

Placeholder scan: This plan contains no TBD/TODO markers or generic test instructions. Interfaces introduced in Task 1 are used consistently in Tasks 1 and 2.

