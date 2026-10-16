import Foundation
import Extensions
import Switches
import Testing
@testable import OnlySwitch

struct BuiltInSwitchCatalogTests {
    @Test("Customize keeps its routing identifier and displays Built-In")
    func customizeSettingsDisplayNameDoesNotChangeItsIdentifier() {
        #expect(SettingsItem.Customize.rawValue == "Customize")
        #expect(SettingsItem.Customize.titleLocalizationKey == "Built-In")
    }

    @Test("Built-In catalog keys have complete English and Simplified Chinese translations")
    func catalogKeysAreLocalized() throws {
        let expectedTranslations = [
            (key: "Built-In", english: "Built-In", simplifiedChinese: "内置"),
            (key: "Search Built-In Switches", english: "Search Built-In Switches", simplifiedChinese: "搜索内置开关"),
            (key: "No Built-In Switches Found", english: "No Built-In Switches Found", simplifiedChinese: "未找到内置开关"),
            (key: "Audio", english: "Audio", simplifiedChinese: "音频"),
            (key: "Display & Appearance", english: "Display & Appearance", simplifiedChinese: "显示与外观"),
            (key: "Desktop & Finder", english: "Desktop & Finder", simplifiedChinese: "桌面与访达"),
            (key: "Cleanup & Storage", english: "Cleanup & Storage", simplifiedChinese: "清理与存储"),
            (key: "Productivity & Tools", english: "Productivity & Tools", simplifiedChinese: "效率与工具"),
            (key: "Other", english: "Other", simplifiedChinese: "其他")
        ]
        let catalog = try localizationCatalog()

        for expected in expectedTranslations {
            let entry = try #require(catalog[expected.key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(localizedValue(in: localizations, language: "en") == expected.english)
            #expect(localizedValue(in: localizations, language: "zh-Hans") == expected.simplifiedChinese)
        }
    }

    @Test("Every Built-In catalog key covers the app's existing languages")
    func catalogKeysCoverEveryLanguage() throws {
        let keys = [
            "Built-In", "Search Built-In Switches", "No Built-In Switches Found",
            "Audio", "Display & Appearance", "Desktop & Finder",
            "Cleanup & Storage", "Productivity & Tools", "Other",
            "Dock Preview",
            "Dock Preview requires Accessibility and Screen Recording permissions.",
            "Window preview unavailable", "Unable to activate window"
        ]
        let catalog = try localizationCatalog()
        let supportedLanguages: Set<String> = [
            "cs", "de", "en", "es", "fil", "fr", "hr", "it", "ja", "ko",
            "nl", "pl", "pt-BR", "ru", "sk", "so", "tr", "uk", "zh-Hans", "zh-Hant"
        ]

        for key in keys {
            let entry = try #require(catalog[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(localizations.keys) == supportedLanguages, "Missing translations for \(key)")
            #expect(localizations.keys.allSatisfy {
                guard let value = localizedValue(in: localizations, language: $0) else { return false }
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }, "Empty translation for \(key)")
        }
    }

    @Test("Every switch belongs to exactly one functional section")
    func sectionsCoverEverySwitchExactlyOnce() {
        let grouped = BuiltInSwitchCatalog.sectioned(types: SwitchType.allCases)
        let groupedTypes = grouped.flatMap(\.types)

        #expect(groupedTypes.count == SwitchType.allCases.count)
        #expect(Set(groupedTypes).count == SwitchType.allCases.count)
        #expect(Set(groupedTypes) == Set(SwitchType.allCases))
    }

    @Test("Switch ordering inside each section follows SwitchType.allCases")
    func sectionOrderingIsStable() {
        let sourceIndexes = Dictionary(
            uniqueKeysWithValues: SwitchType.allCases.enumerated().map { ($1, $0) }
        )

        for group in BuiltInSwitchCatalog.sectioned(types: SwitchType.allCases) {
            let indexes = group.types.compactMap { sourceIndexes[$0] }
            #expect(indexes == indexes.sorted(), "Ordering changed in \(group.section)")
        }
    }

    @Test("Audio controls are grouped together")
    func audioSectionContainsRelatedControls() throws {
        let audio = try #require(
            BuiltInSwitchCatalog.sectioned(types: SwitchType.allCases)
                .first(where: { $0.section == .audio })
        )

        #expect(audio.types.contains(.mute))
        #expect(audio.types.contains(.muteMicrophone))
        #expect(audio.types.contains(.soundMixer))
        #expect(audio.types.contains(.applemusic))
    }

    @Test("Dock Preview is listed with Desktop & Finder switches")
    func dockPreviewIsInDesktopAndFinder() {
        #expect(BuiltInSwitchCatalog.section(for: .dockPreview) == .desktopAndFinder)
        #expect(SwitchType.dockPreview.barInfo().title == "Dock Preview")
        #expect(SwitchType.dockPreview.barInfo().controlType == .Switch)
    }

    @MainActor
    @Test("Dock Preview switch controls enabled intent without changing card visibility")
    func dockPreviewSwitchPreservesCustomizeVisibility() async throws {
        let suite = "DockPreviewSwitchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SwitchVisibilityState.setVisibleTypes([.darkMode], in: defaults)

        let control = DockPreviewSwitch(
            enabled: { defaults.bool(forKey: UserDefaults.Key.dockPreviewEnabled) },
            setEnabled: { defaults.set($0, forKey: UserDefaults.Key.dockPreviewEnabled) }
        )
        #expect(control.type == .dockPreview)
        #expect(await control.currentStatus() == false)

        try await control.operateSwitch(isOn: true)
        #expect(await control.currentStatus())
        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == [.darkMode])

        try await control.operateSwitch(isOn: false)
        #expect(await control.currentStatus() == false)
        #expect(SwitchVisibilityState.visibleTypes(from: defaults) == [.darkMode])
    }

    @Test("Search matches the injected current-language title")
    func localizedQueryMatchesLocalizedTitle() {
        let matches = BuiltInSwitchCatalog.matches(
            sourceTitle: "Dark Mode",
            query: "深色",
            locale: Locale(identifier: "zh-Hans"),
            localize: { $0 == "Dark Mode" ? "深色模式" : $0 }
        )

        #expect(matches)
    }

    @Test("Search falls back to the source title")
    func queryFallsBackToSourceTitle() {
        let matches = BuiltInSwitchCatalog.matches(
            sourceTitle: "Dark Mode",
            query: "dark",
            locale: Locale(identifier: "en_US_POSIX"),
            localize: { _ in "深色模式" }
        )

        #expect(matches)
    }

    @Test("Search ignores case, diacritics, and character width", arguments: [
        (candidate: "CAFÉ", query: "cafe"),
        (candidate: "Ｍｕｔｅ", query: "mute")
    ])
    func searchComparisonIsUserFriendly(example: (candidate: String, query: String)) {
        let matches = BuiltInSwitchCatalog.matches(
            sourceTitle: example.candidate,
            query: example.query,
            locale: Locale(identifier: "en_US_POSIX"),
            localize: { $0 }
        )

        #expect(matches)
    }

    @Test("Search uses the app language locale instead of Turkish system casing rules")
    func searchUsesExplicitAppLanguageLocale() {
        let englishAppLanguageMatch = BuiltInSwitchCatalog.matches(
            sourceTitle: "HIDE",
            query: "hide",
            locale: Locale(identifier: "en"),
            localize: { $0 }
        )
        let turkishLocaleMatch = BuiltInSwitchCatalog.matches(
            sourceTitle: "HIDE",
            query: "hide",
            locale: Locale(identifier: "tr"),
            localize: { $0 }
        )

        #expect(englishAppLanguageMatch)
        #expect(turkishLocaleMatch == false)
    }

    @Test("Whitespace-only queries match every title")
    func whitespaceQueryMatchesEveryTitle() {
        #expect(BuiltInSwitchCatalog.matches(
            sourceTitle: "Mute",
            query: " \n\t ",
            locale: Locale(identifier: "en_US_POSIX"),
            localize: { $0 }
        ))
    }

    @MainActor
    @Test("A localized section-title match returns the entire section")
    func localizedSectionTitleReturnsWholeGroup() throws {
        let items = [SwitchType.mute, .soundMixer, .darkMode].map {
            CustomizeItem(type: $0, toggle: true, error: { _ in })
        }

        let sections = BuiltInSwitchCatalog.sections(
            items: items,
            matching: "声音",
            locale: Locale(identifier: "zh-Hans"),
            localize: { key in key == "Audio" ? "声音" : key }
        )
        let audio = try #require(sections.first(where: { $0.section == .audio }))

        #expect(audio.items.map(\.type) == [.mute, .soundMixer])
        #expect(sections.contains(where: { $0.section == .displayAndAppearance }) == false)
    }

    @MainActor
    @Test("Sections with no matching items are omitted")
    func unmatchedQueryReturnsNoSections() {
        let items = [SwitchType.mute, .darkMode].map {
            CustomizeItem(type: $0, toggle: true, error: { _ in })
        }

        let sections = BuiltInSwitchCatalog.sections(
            items: items,
            matching: "not-a-switch",
            locale: Locale(identifier: "en_US_POSIX"),
            localize: { $0 }
        )

        #expect(sections.isEmpty)
    }

    private func localizationCatalog() throws -> [String: Any] {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repositoryURL
            .appendingPathComponent("Localization")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(root["strings"] as? [String: Any])
    }

    private func localizedValue(
        in localizations: [String: Any],
        language: String
    ) -> String? {
        guard
            let localization = localizations[language] as? [String: Any],
            let stringUnit = localization["stringUnit"] as? [String: Any]
        else {
            return nil
        }
        return stringUnit["value"] as? String
    }
}
