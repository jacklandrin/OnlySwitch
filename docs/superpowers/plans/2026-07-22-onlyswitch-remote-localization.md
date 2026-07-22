# OnlySwitch Remote Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate all 115 user-facing OnlySwitch Remote strings into the 19 locales already supported by the Mac app.

**Architecture:** Keep English source keys unchanged and add standard Xcode String Catalog `localizations` entries directly to the existing Remote catalog. Work through sequential locale groups because all translations share one file, using the Mac catalog as the terminology source and machine-readable checks after every group.

**Tech Stack:** Xcode String Catalog (`.xcstrings` JSON), `jq`, Git, Xcode 18 toolchain

## Global Constraints

- Modify `OnlySwitchRemote/Localizable.xcstrings`; do not change Swift source or the Mac app catalog.
- Support exactly `cs`, `de`, `es`, `fil`, `fr`, `hr`, `it`, `ja`, `ko`, `nl`, `pl`, `pt-BR`, `ru`, `sk`, `so`, `tr`, `uk`, `zh-Hans`, and `zh-Hant`.
- Reuse terminology from `Localization/Localizable.xcstrings` when an English key or product concept already exists.
- Preserve every English source key and all `%@` and `%lld` placeholder types and occurrence counts.
- Every localized string unit must have `state: "translated"` and a non-empty `value`.
- Keep OnlySwitch, Mac, iOS, VoiceOver, AirPods, Xcode, and Apple Music unchanged where natural for the locale.
- Preserve the severity and recovery meaning of warnings and destructive confirmation copy.
- Do not stage or modify unrelated user-owned files, including `OnlySwitch.xcodeproj/project.pbxproj` and `.superpowers/`.

---

### Task 1: Establish the Catalog Baseline and Failing Coverage Check

**Files:**
- Inspect: `OnlySwitchRemote/Localizable.xcstrings`
- Reference: `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: the 115 English source keys in the Remote catalog
- Produces: a verified baseline against commit `ef54a06` and a repeatable locale-coverage query used by later tasks

- [ ] **Step 1: Confirm the source-key baseline**

Run:

```bash
rtk jq -e '.sourceLanguage == "en" and (.strings | length == 115)' OnlySwitchRemote/Localizable.xcstrings
```

Expected: `true` and exit status 0.

- [ ] **Step 2: Run the all-locale coverage check before translation**

Run:

```bash
rtk jq -e --argjson locales '["cs","de","es","fil","fr","hr","it","ja","ko","nl","pl","pt-BR","ru","sk","so","tr","uk","zh-Hans","zh-Hant"]' '
  [.strings | to_entries[] | .key as $key | $locales[] as $locale |
    select(
      .value.localizations[$locale].stringUnit.state != "translated" or
      ((.value.localizations[$locale].stringUnit.value // "") | length) == 0
    ) | {key: $key, locale: $locale}
  ] | length == 0
' OnlySwitchRemote/Localizable.xcstrings
```

Expected: `false` and a nonzero exit status because the 19 translations have not been added.

- [ ] **Step 3: Record the clean baseline state**

Run:

```bash
rtk git status --short
```

Expected: no localization-catalog modification; only pre-existing user-owned changes may appear.

### Task 2: Translate the Core Western European Locales

**Files:**
- Modify: `OnlySwitchRemote/Localizable.xcstrings`
- Reference: `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: the English source key and any matching Mac-catalog values
- Produces: complete `de`, `es`, `fr`, `it`, `nl`, and `pt-BR` string units for all 115 keys

- [ ] **Step 1: Add German, Spanish, French, Italian, Dutch, and Brazilian Portuguese values**

For every entry under `strings`, add these six locale objects using the standard catalog form. For example, `Cancel` must contain:

```json
"de": { "stringUnit": { "state": "translated", "value": "Abbrechen" } },
"es": { "stringUnit": { "state": "translated", "value": "Cancelar" } },
"fr": { "stringUnit": { "state": "translated", "value": "Annuler" } },
"it": { "stringUnit": { "state": "translated", "value": "Annulla" } },
"nl": { "stringUnit": { "state": "translated", "value": "Annuleer" } },
"pt-BR": { "stringUnit": { "state": "translated", "value": "Cancelar" } }
```

Copy exact established values from the Mac catalog when available; otherwise translate the full Remote-specific sentence naturally.

- [ ] **Step 2: Validate this locale group**

Run:

```bash
rtk jq -e --argjson locales '["de","es","fr","it","nl","pt-BR"]' '
  [.strings | to_entries[] | .key as $key | $locales[] as $locale |
    select(.value.localizations[$locale].stringUnit.state != "translated" or ((.value.localizations[$locale].stringUnit.value // "") | length) == 0)
  ] | length == 0
' OnlySwitchRemote/Localizable.xcstrings
```

Expected: `true` and exit status 0.

- [ ] **Step 3: Commit the completed group**

```bash
rtk git add OnlySwitchRemote/Localizable.xcstrings
rtk git commit -m "l10n: add western European Remote translations"
```

### Task 3: Translate Central and Eastern European Locales

**Files:**
- Modify: `OnlySwitchRemote/Localizable.xcstrings`
- Reference: `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: the catalog completed through Task 2
- Produces: complete `cs`, `hr`, `pl`, `ru`, `sk`, and `uk` string units for all 115 keys

- [ ] **Step 1: Add Czech, Croatian, Polish, Russian, Slovak, and Ukrainian values**

Add all six locale entries to every source string. Use established Mac-app terms for shared controls and use natural grammatical cases around `%@`; never translate or alter the placeholder itself.

- [ ] **Step 2: Validate this locale group**

Run:

```bash
rtk jq -e --argjson locales '["cs","hr","pl","ru","sk","uk"]' '
  [.strings | to_entries[] | .key as $key | $locales[] as $locale |
    select(.value.localizations[$locale].stringUnit.state != "translated" or ((.value.localizations[$locale].stringUnit.value // "") | length) == 0)
  ] | length == 0
' OnlySwitchRemote/Localizable.xcstrings
```

Expected: `true` and exit status 0.

- [ ] **Step 3: Commit the completed group**

```bash
rtk git add OnlySwitchRemote/Localizable.xcstrings
rtk git commit -m "l10n: add central and eastern European Remote translations"
```

### Task 4: Translate Turkish, Filipino, and Somali

**Files:**
- Modify: `OnlySwitchRemote/Localizable.xcstrings`
- Reference: `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: the catalog completed through Task 3
- Produces: complete `fil`, `so`, and `tr` string units for all 115 keys

- [ ] **Step 1: Add Filipino, Somali, and Turkish values**

Translate all UI labels, status text, instructions, confirmations, and accessibility labels. Prefer familiar platform terminology over literal wording, while keeping the exact connection, retry, unavailable-state, and destructive-removal meaning.

- [ ] **Step 2: Validate this locale group**

Run:

```bash
rtk jq -e --argjson locales '["fil","so","tr"]' '
  [.strings | to_entries[] | .key as $key | $locales[] as $locale |
    select(.value.localizations[$locale].stringUnit.state != "translated" or ((.value.localizations[$locale].stringUnit.value // "") | length) == 0)
  ] | length == 0
' OnlySwitchRemote/Localizable.xcstrings
```

Expected: `true` and exit status 0.

- [ ] **Step 3: Commit the completed group**

```bash
rtk git add OnlySwitchRemote/Localizable.xcstrings
rtk git commit -m "l10n: add Filipino Somali and Turkish Remote translations"
```

### Task 5: Translate East Asian Locales

**Files:**
- Modify: `OnlySwitchRemote/Localizable.xcstrings`
- Reference: `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: the catalog completed through Task 4
- Produces: complete `ja`, `ko`, `zh-Hans`, and `zh-Hant` string units for all 115 keys

- [ ] **Step 1: Add Japanese, Korean, Simplified Chinese, and Traditional Chinese values**

Use concise native UI phrasing and locale-appropriate punctuation. Maintain distinct Simplified and Traditional Chinese terminology rather than mechanically converting characters, especially for Settings, pairing, dashboard layout, offline status, retry actions, and accessibility labels.

- [ ] **Step 2: Validate this locale group**

Run:

```bash
rtk jq -e --argjson locales '["ja","ko","zh-Hans","zh-Hant"]' '
  [.strings | to_entries[] | .key as $key | $locales[] as $locale |
    select(.value.localizations[$locale].stringUnit.state != "translated" or ((.value.localizations[$locale].stringUnit.value // "") | length) == 0)
  ] | length == 0
' OnlySwitchRemote/Localizable.xcstrings
```

Expected: `true` and exit status 0.

- [ ] **Step 3: Commit the completed group**

```bash
rtk git add OnlySwitchRemote/Localizable.xcstrings
rtk git commit -m "l10n: add East Asian Remote translations"
```

### Task 6: Validate Translation Integrity and Build the App

**Files:**
- Verify: `OnlySwitchRemote/Localizable.xcstrings`
- Verify unchanged: `Localization/Localizable.xcstrings`
- Verify unchanged: `OnlySwitchRemote/**/*.swift`

**Interfaces:**
- Consumes: all 19 completed locale sets
- Produces: evidence that source keys, coverage, placeholders, JSON structure, and the iOS build are valid

- [ ] **Step 1: Validate JSON, locale coverage, state, and non-empty values**

Run:

```bash
rtk jq -e --argjson locales '["cs","de","es","fil","fr","hr","it","ja","ko","nl","pl","pt-BR","ru","sk","so","tr","uk","zh-Hans","zh-Hant"]' '
  [.strings | to_entries[] | .key as $key | $locales[] as $locale |
    select(
      .value.localizations[$locale].stringUnit.state != "translated" or
      ((.value.localizations[$locale].stringUnit.value // "") | length) == 0
    ) | {key: $key, locale: $locale}
  ] | length == 0
' OnlySwitchRemote/Localizable.xcstrings
```

Expected: `true` and exit status 0.

- [ ] **Step 2: Validate placeholder type and count parity**

Run:

```bash
rtk jq -e --argjson locales '["cs","de","es","fil","fr","hr","it","ja","ko","nl","pl","pt-BR","ru","sk","so","tr","uk","zh-Hans","zh-Hant"]' '
  [.strings | to_entries[] | .key as $key |
    ($key | [scan("%(?:@|lld)")] | sort) as $sourcePlaceholders |
    $locales[] as $locale |
    (.value.localizations[$locale].stringUnit.value // "") as $value |
    select(($value | [scan("%(?:@|lld)")] | sort) != $sourcePlaceholders) |
    {key: $key, locale: $locale, value: $value}
  ] | length == 0
' OnlySwitchRemote/Localizable.xcstrings
```

Expected: `true` and exit status 0.

- [ ] **Step 3: Prove the 115 English source keys are unchanged**

Run:

```bash
diff <(rtk git show ef54a06:OnlySwitchRemote/Localizable.xcstrings | rtk jq -S '.strings | keys') <(rtk jq -S '.strings | keys' OnlySwitchRemote/Localizable.xcstrings)
```

Expected: no output and exit status 0.

- [ ] **Step 4: Inspect the diff for scope and translation quality**

Run:

```bash
rtk git diff ef54a06 -- OnlySwitchRemote/Localizable.xcstrings
rtk git diff --name-only ef54a06
```

Expected: the catalog diff changes only localization objects; the task commits add only the Remote catalog and documentation. Review every locale's pairing, offline, retry, destructive removal, format-string, and accessibility examples, then review all values for `de`, `es`, `fr`, `pt-BR`, `ru`, `tr`, `uk`, `ja`, `ko`, `zh-Hans`, and `zh-Hant`.

- [ ] **Step 5: Build the iOS Remote target**

Run:

```bash
rtk xcodebuild -project OnlySwitch.xcodeproj -scheme OnlySwitchRemote -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`. Treat only the previously accepted Xcode toolchain baseline failure as non-localization-related; any String Catalog compiler error must be fixed.

- [ ] **Step 6: Confirm a clean scoped result**

Run:

```bash
rtk git status --short
```

Expected: no uncommitted localization changes. Any displayed project-file or `.superpowers/` changes remain untouched and user-owned.
