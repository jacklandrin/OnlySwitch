# Desktop Pet 2.7.0 Release Content Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Localize the Desktop Pet setting across every supported language, release the app and widget as 2.7.0, and document the feature in the README.

**Architecture:** Extend the existing manual `Show Desktop Pet` string-catalog entry to all 20 supported locales without creating a second key. Update only shipping-target `MARKETING_VERSION` values and add a concise README paragraph next to the existing release feature history.

**Tech Stack:** Xcode string catalog JSON, Xcode project settings, Markdown, jq, Swift Package Manager

## Global Constraints

- Keep the key exactly `Show Desktop Pet` with `extractionState` set to `manual`.
- Include every catalog locale: `cs`, `de`, `en`, `es`, `fil`, `fr`, `hr`, `it`, `ja`, `ko`, `nl`, `pl`, `pt-BR`, `ru`, `sk`, `so`, `tr`, `uk`, `zh-Hans`, and `zh-Hant`.
- Use natural, product-appropriate UI wording where literal “pet” is awkward.
- Set `MARKETING_VERSION = 2.7.0` only for the OnlySwitch and OnlyWidgetExtension Debug/Release configurations.
- Do not alter `CURRENT_PROJECT_VERSION = 258` or the OnlySwitchTests marketing version.

---

### Task 1: Complete the Desktop Pet localization entry

**Files:**
- Modify: `Localization/Localizable.xcstrings`

**Interfaces:**
- Produces: a `Show Desktop Pet` localization for all 20 supported locale codes.

- [ ] **Step 1: Verify the catalog is incomplete**

Run:

```bash
rtk jq -r '.strings["Show Desktop Pet"].localizations | keys[]' Localization/Localizable.xcstrings
```

Expected: only `en`, `zh-Hans`, and `zh-Hant` are printed.

- [ ] **Step 2: Add the missing translated values**

Add each locale below with `state: "translated"`:

| Locale | Value |
| --- | --- |
| cs | Zobrazit mazlíčka na ploše |
| de | Desktop-Haustier anzeigen |
| es | Mostrar mascota de escritorio |
| fil | Ipakita ang Desktop Pet |
| fr | Afficher le compagnon de bureau |
| hr | Prikaži ljubimca na radnoj površini |
| it | Mostra la mascotte sul desktop |
| ja | デスクトップペットを表示 |
| ko | 데스크톱 펫 표시 |
| nl | Desktop-huisdier tonen |
| pl | Pokaż pupila na pulpicie |
| pt-BR | Mostrar mascote da área de trabalho |
| ru | Показывать питомца на рабочем столе |
| sk | Zobraziť zvieratko na ploche |
| so | Muuji Xayawaanka Desktop-ka |
| tr | Masaüstü evcil hayvanını göster |
| uk | Показувати улюбленця на робочому столі |

- [ ] **Step 3: Validate complete locale coverage and JSON**

Run:

```bash
rtk jq -e '(.strings["Show Desktop Pet"].localizations | keys | length) == 20' Localization/Localizable.xcstrings
```

Expected: exit code 0 and `true`.

### Task 2: Set release version and document the feature

**Files:**
- Modify: `OnlySwitch.xcodeproj/project.pbxproj`
- Modify: `README.md`

**Interfaces:**
- Produces: OnlySwitch and OnlyWidgetExtension shipping configurations with `MARKETING_VERSION = 2.7.0`.
- Produces: a README description of enabling, dragging, and clicking the Desktop Pet.

- [ ] **Step 1: Update shipping target versions**

Replace the six `MARKETING_VERSION = 2.6.10;` settings for the OnlySwitch and OnlyWidgetExtension Debug/Release configurations with:

```text
MARKETING_VERSION = 2.7.0;
```

- [ ] **Step 2: Add the README feature paragraph**

Place this paragraph after the existing “Only Control appearance” version history:

```markdown
Since Version 2.7.0, OnlySwitch includes an optional **Desktop Pet**: a small, always-on-top desktop companion. Enable it in General settings, drag it to place it anywhere on screen, and click it to show or dismiss Only Control.
```

- [ ] **Step 3: Verify exact release settings and documentation**

Run:

```bash
rtk rg -n 'MARKETING_VERSION = 2\.7\.0|Desktop Pet' OnlySwitch.xcodeproj/project.pbxproj README.md
```

Expected: six `2.7.0` shipping settings and the new README paragraph.

### Task 3: Full verification and release commit

**Files:**
- Review all modified release-content and pending drag-fix files.

**Interfaces:**
- Produces: one verified feature branch commit.

- [ ] **Step 1: Check catalog and diff formatting**

Run:

```bash
rtk jq empty Localization/Localizable.xcstrings
rtk git diff --check
```

Expected: both commands exit 0.

- [ ] **Step 2: Run the full module suite and strict-concurrency app build**

Run:

```bash
rtk swift test --package-path Modules
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitch -configuration Debug -sdk macosx SWIFT_STRICT_CONCURRENCY=complete build
```

Expected: all 23 module tests pass and the app build exits 0.

- [ ] **Step 3: Commit**

```bash
rtk git add Localization/Localizable.xcstrings OnlySwitch.xcodeproj/project.pbxproj README.md Modules/Sources/DesktopPet/DesktopPetInteractionShape.swift Modules/Sources/DesktopPet/DesktopPetRootView.swift Modules/Tests/ModulesTests/DesktopPetLayoutTests.swift docs/superpowers/plans/2026-07-13-desktop-pet-hit-testing.md docs/superpowers/plans/2026-07-13-desktop-pet-release.md
rtk git commit -m "feat: release desktop pet"
```
