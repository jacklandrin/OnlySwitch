# OnlySwitch Remote Localization Design

## Goal

Translate every user-facing string in `OnlySwitchRemote/Localizable.xcstrings` into the same 19 locales supported by the Mac app:

- Czech (`cs`)
- German (`de`)
- Spanish (`es`)
- Filipino (`fil`)
- French (`fr`)
- Croatian (`hr`)
- Italian (`it`)
- Japanese (`ja`)
- Korean (`ko`)
- Dutch (`nl`)
- Polish (`pl`)
- Brazilian Portuguese (`pt-BR`)
- Russian (`ru`)
- Slovak (`sk`)
- Somali (`so`)
- Turkish (`tr`)
- Ukrainian (`uk`)
- Simplified Chinese (`zh-Hans`)
- Traditional Chinese (`zh-Hant`)

## Translation Approach

Reuse established translations and terminology from `Localization/Localizable.xcstrings` whenever an English key or product concept already exists. Translate remote-specific pairing, networking, dashboard, status, retry, and accessibility copy consistently with the Mac app's tone.

Translations should sound natural in each locale rather than mechanically mirroring English word order. Product and platform names such as OnlySwitch, Mac, iOS, VoiceOver, AirPods, Xcode, and Apple Music remain unchanged where appropriate.

## Catalog Structure

Each source string receives a `localizations` entry for all 19 locale identifiers. Every string unit uses `state: "translated"` and a localized `value`. The English source keys remain unchanged.

Format placeholders must be preserved exactly:

- `%@` remains `%@` with the same occurrence count.
- `%lld` remains `%lld` with the same occurrence count.
- Locale-specific sentence structure may move a placeholder, but may not change its type or remove it.

Curly apostrophes, ellipses, em dashes, and punctuation may be adapted to natural locale conventions without changing runtime meaning.

## Quality and Consistency

Use consistent translations for repeated concepts including Settings, Dashboard, Mac, Pairing Code, Offline, Connected, Retry, Cancel, Run, On, Off, Working, and unavailable states. Accessibility labels must remain concise and action-oriented.

Warnings must retain their severity and recovery instruction. Destructive copy for forgetting a Mac must clearly state that credentials, cached controls, statuses, and layout are removed from the device.

## Validation

Validation must confirm:

1. The catalog parses as valid JSON.
2. Every source key has all 19 locale entries.
3. Every locale entry is marked `translated` and has a non-empty value.
4. Placeholder types and counts match the English source key.
5. No source keys are added, removed, or renamed.
6. The iOS Remote target builds with the completed catalog.

A final language-quality review will sample pairing, connection, destructive, dashboard, and accessibility strings across every locale and check the complete Chinese, Japanese, Korean, German, French, Spanish, Portuguese, Russian, Turkish, and Ukrainian sets for terminology consistency.

## Scope

Only `OnlySwitchRemote/Localizable.xcstrings`, localization validation tests or scripts needed by the repository, and the design/plan documents are in scope. The Mac app catalog and Swift source code remain unchanged.
