import Foundation
import Testing
@testable import Extensions

struct SettingsBackupTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func roundTripPreservesAllSections() throws {
        let orderDic = ["1": 3, "2": 1]
        let backup = SettingsBackup(
            preferences: [
                UserDefaults.Key.orderWeight: orderDic,
                UserDefaults.Key.menubarIcon: "menubar_2",
                "KeyboardShortcuts_invokePopover": "{\"carbonKeyCode\":1}",
            ],
            sharedPreferences: [UserDefaults.Key.AppLanguage: "tr"],
            radioStations: [RadioStationBackup(title: "Example FM", url: "https://example.com/stream")],
            evolution: EvolutionBackup(
                preExecution: "export PATH=/opt/homebrew/bin:$PATH",
                commands: [["id": UUID().uuidString, "name": "Say hi", "itemType": "Button", "singleCommand": "echo hi"]]
            )
        )

        let decoded = try SettingsBackup(data: try backup.encoded())

        #expect(decoded.preferences[UserDefaults.Key.orderWeight] as? [String: Int] == orderDic)
        #expect(decoded.preferences[UserDefaults.Key.menubarIcon] as? String == "menubar_2")
        #expect(decoded.preferences["KeyboardShortcuts_invokePopover"] as? String == "{\"carbonKeyCode\":1}")
        #expect(decoded.sharedPreferences[UserDefaults.Key.AppLanguage] as? String == "tr")
        #expect(decoded.radioStations == backup.radioStations)
        #expect(decoded.evolution == backup.evolution)
    }

    @Test func decodingDropsKeysOutsideTheAllowlist() throws {
        let root: [String: Any] = [
            "formatVersion": 1,
            "preferences": [
                UserDefaults.Key.claudeAPI: "sk-should-not-import",
                UserDefaults.Key.authenticatorAccounts: "secret",
                "NSSomeSystemKey": true,
                UserDefaults.Key.showAds: false,
            ],
            "sharedPreferences": [UserDefaults.Key.AppLanguage: "de", "unrelated": 1],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)

        let decoded = try SettingsBackup(data: data)

        #expect(Set(decoded.preferences.keys) == [UserDefaults.Key.showAds])
        #expect(Set(decoded.sharedPreferences.keys) == [UserDefaults.Key.AppLanguage])
    }

    @Test func evolutionCommandsKeepOnlyKnownFields() {
        let evolution = EvolutionBackup(preExecution: nil, commands: [["name": "x", "unexpected": "y"]])
        #expect(evolution.commands == [["name": "x"]])
        #expect(!evolution.isEmpty)
        #expect(EvolutionBackup(preExecution: "", commands: []).isEmpty)
    }

    @Test func collectReadsOnlyExportableKeys() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UserDefaults.Key.showDesktopPet)
        defaults.set("secret", forKey: UserDefaults.Key.openAIAPI)
        defaults.set("{}", forKey: "KeyboardShortcuts_1")

        let collected = SettingsBackup.collectPreferences(from: defaults)

        #expect(collected[UserDefaults.Key.showDesktopPet] as? Bool == true)
        #expect(collected["KeyboardShortcuts_1"] as? String == "{}")
        #expect(collected[UserDefaults.Key.openAIAPI] == nil)
    }

    @Test func replaceWritesValuesAndResetsMissingSettingsOnly() {
        let defaults = makeDefaults()
        defaults.set(0.9, forKey: UserDefaults.Key.nightShiftStrength)
        defaults.set("{}", forKey: "KeyboardShortcuts_old")
        defaults.set("keep-me", forKey: UserDefaults.Key.claudeAPI)

        SettingsBackup.replace(
            [UserDefaults.Key.orderWeight: ["5": 0], UserDefaults.Key.claudeAPI: "from-file"],
            in: defaults,
            isAllowed: SettingsBackup.isExportablePreference
        )

        #expect(defaults.dictionary(forKey: UserDefaults.Key.orderWeight) as? [String: Int] == ["5": 0])
        #expect(defaults.object(forKey: UserDefaults.Key.nightShiftStrength) == nil)
        #expect(defaults.object(forKey: "KeyboardShortcuts_old") == nil)
        #expect(defaults.string(forKey: UserDefaults.Key.claudeAPI) == "keep-me")
    }

    @Test func includesSettingsStoredOutsideTheRegistryNames() {
        #expect(SettingsBackup.isExportablePreference("NSStatusItem Preferred Position Item-0"))
        #expect(SettingsBackup.isExportablePreference(UserDefaults.Key.canPlayEffectSound))
        #expect(SettingsBackup.isExportablePreference(UserDefaults.Key.menubarIcon))
        #expect(SettingsBackup.isExportablePreference(UserDefaults.Key.KeepAwakeKey))
        #expect(SettingsBackup.isExportablePreference(UserDefaults.Key.nightShiftStrength))
        #expect(SettingsBackup.isExportablePreference(UserDefaults.Key.SwitchState))
        #expect(SettingsBackup.isExportablePreference(UserDefaults.Key.orderWeight))
        #expect(SettingsBackup.isExportablePreference(UserDefaults.Key.shortcutsDic))
        #expect(!SettingsBackup.isExportablePreference("remoteAccess.isEnabled"))
    }

    @Test func rejectsGarbageAndNewerVersions() throws {
        #expect(throws: SettingsBackupError.invalidFile) {
            try SettingsBackup(data: Data("not a plist".utf8))
        }
        let newer = try PropertyListSerialization.data(fromPropertyList: ["formatVersion": 99], format: .xml, options: 0)
        #expect(throws: SettingsBackupError.unsupportedVersion(99)) {
            try SettingsBackup(data: newer)
        }
    }
}
