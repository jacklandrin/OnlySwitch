#if os(macOS)
import Extensions
import Foundation
import Testing
@testable import Screenshots

/// In-memory stand-in for `com.apple.screencapture`; tests never write the real domain.
final class InMemoryPreferenceDomain: PreferenceDomain, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any]
    var synchronizeResult: Bool
    init(_ values: [String: Any] = [:], synchronizeResult: Bool = true) { storage = values; self.synchronizeResult = synchronizeResult }
    func value(forKey key: String) -> Any? { lock.lock(); defer { lock.unlock() }; return storage[key] }
    func set(_ value: Any?, forKey key: String) { lock.lock(); defer { lock.unlock() }; storage[key] = value }
    func synchronize() -> Bool { lock.lock(); defer { lock.unlock() }; return synchronizeResult }
    var keys: Set<String> { lock.lock(); defer { lock.unlock() }; return Set(storage.keys) }
}

struct ScreenCapturePreferencesTests {
    struct Fixture {
        let root: URL
        let domain: InMemoryPreferenceDomain
        let locationKey: String
        let backup = InMemoryPreferenceDomain()
        var folder: URL { root.appendingPathComponent("OnlySwitch Screenshots", isDirectory: true) }
        init(_ values: [String: Any] = [:], locationKey: String = "location") throws {
            root = try makeTemporaryDirectory()
            domain = InMemoryPreferenceDomain(values)
            self.locationKey = locationKey
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        var preferences: ScreenCapturePreferences { ScreenCapturePreferences(domain: domain, backup: backup, folder: folder, locationKey: locationKey) }
    }

    @Test func enableBacksUpAndRedirectsLocationAndHidesThumbnail() throws {
        let fixture = try Fixture(["location": "/Users/example/Desktop", "show-thumbnail": true]); defer { fixture.remove() }
        try fixture.preferences.enable()
        #expect(fixture.domain.value(forKey: "location") as? String == fixture.folder.path)
        #expect(fixture.domain.value(forKey: "show-thumbnail") as? Bool == false)
        let data = try #require(fixture.backup.value(forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings) as? Data)
        #expect(try JSONDecoder().decode(ScreenshotCaptureSettings.self, from: data) == ScreenshotCaptureSettings(location: "/Users/example/Desktop", showThumbnail: true))
        #expect(fixture.backup.value(forKey: UserDefaults.Key.screenshotsCaptureEnabled) as? Bool == true)
        #expect(fixture.preferences.isEnabled)
        #expect(fixture.preferences.status(enabledFlag: true) == .active)
    }

    @Test func disableRestoresPreviousValuesIncludingAbsentKeys() throws {
        let fixture = try Fixture(["show-thumbnail": true, "type": "png"]); defer { fixture.remove() }
        try fixture.preferences.enable()
        try fixture.preferences.disable()
        #expect(fixture.domain.keys == ["show-thumbnail", "type"])
        #expect(fixture.domain.value(forKey: "show-thumbnail") as? Bool == true)
        #expect(fixture.backup.keys.isEmpty || fixture.backup.value(forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings) == nil)
        #expect(!fixture.preferences.isEnabled)
        #expect(fixture.preferences.status(enabledFlag: false) == .disabled)
    }

    @Test func disableWithoutBackupFallsBackToSystemDefaults() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        fixture.domain.set(fixture.folder.path, forKey: "location")
        fixture.domain.set(false, forKey: "show-thumbnail")
        fixture.backup.set(true, forKey: UserDefaults.Key.screenshotsCaptureEnabled)
        try fixture.preferences.disable()
        #expect(fixture.domain.keys.isEmpty)
        #expect(!fixture.preferences.isEnabled)
    }

    @Test func enablingTwiceKeepsTheOriginalBackup() throws {
        let fixture = try Fixture(["location": "/Volumes/Shots"]); defer { fixture.remove() }
        try fixture.preferences.enable()
        try fixture.preferences.enable()
        try fixture.preferences.disable()
        #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Shots")
        #expect(fixture.domain.keys == ["location"])
    }

    @Test func modernCaptureUsesEffectiveLocationWithoutChangingLegacyLocation() throws {
        let fixture = try Fixture(["location": "/Volumes/Legacy", "location-screenshot": "/Volumes/Current"], locationKey: "location-screenshot")
        defer { fixture.remove() }
        try fixture.preferences.enable()
        #expect(fixture.domain.value(forKey: "location-screenshot") as? String == fixture.folder.path)
        #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Legacy")
        #expect(fixture.preferences.status(enabledFlag: true) == .active)
        let data = try #require(fixture.backup.value(forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings) as? Data)
        #expect(try JSONDecoder().decode(ScreenshotCaptureSettings.self, from: data) == ScreenshotCaptureSettings(location: "/Volumes/Legacy", screenshotLocation: "/Volumes/Current", showThumbnail: nil))
        fixture.domain.set("/Volumes/Changed", forKey: "location-screenshot")
        fixture.domain.set(fixture.folder.path, forKey: "location")
        #expect(fixture.preferences.status(enabledFlag: true) == .changedElsewhere)
    }

    @Test func defaultCaptureLocationKeyMatchesRuntimeOS() throws {
        let fixture = try Fixture(["location": "/Volumes/Legacy", "location-screenshot": "/Volumes/Current"])
        defer { fixture.remove() }
        let preferences = ScreenCapturePreferences(domain: fixture.domain, backup: fixture.backup, folder: fixture.folder)
        try preferences.enable()
        if #available(macOS 27, *) {
            #expect(fixture.domain.value(forKey: "location-screenshot") as? String == fixture.folder.path)
            #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Legacy")
        } else {
            #expect(fixture.domain.value(forKey: "location") as? String == fixture.folder.path)
            #expect(fixture.domain.value(forKey: "location-screenshot") as? String == "/Volumes/Current")
        }
        #expect(preferences.status(enabledFlag: true) == .active)
    }

    @Test func modernDisableRestoresBothOwnedLocationsExactly() throws {
        let fixture = try Fixture(["location": "/Volumes/Legacy", "location-screenshot": "/Volumes/Current", "show-thumbnail": true], locationKey: "location-screenshot")
        defer { fixture.remove() }
        try fixture.preferences.enable()
        // Both keys may point at OnlySwitch after migration from an older macOS version.
        fixture.domain.set(fixture.folder.path, forKey: "location")
        try fixture.preferences.disable()
        #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Legacy")
        #expect(fixture.domain.value(forKey: "location-screenshot") as? String == "/Volumes/Current")
        #expect(fixture.domain.value(forKey: "show-thumbnail") as? Bool == true)
        #expect(fixture.preferences.isEnabled == false)
    }

    @Test func modernDisableWithLegacyBackupPreservesUnrecordedModernLocation() throws {
        let fixture = try Fixture(locationKey: "location-screenshot")
        defer { fixture.remove() }
        let oldBackup = Data(#"{"location":"/Volumes/Original","showThumbnail":true}"#.utf8)
        fixture.backup.set(oldBackup, forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings)
        fixture.backup.set(true, forKey: UserDefaults.Key.screenshotsCaptureEnabled)
        fixture.domain.set(fixture.folder.path, forKey: "location")
        fixture.domain.set("/Volumes/External", forKey: "location-screenshot")
        fixture.domain.set(false, forKey: "show-thumbnail")
        try fixture.preferences.disable()
        #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Original")
        #expect(fixture.domain.value(forKey: "location-screenshot") as? String == "/Volumes/External")
        #expect(fixture.domain.value(forKey: "show-thumbnail") as? Bool == true)
        #expect(fixture.preferences.isEnabled == false)
    }

    @Test func modernReapplyEnrichesLegacyBackupAndRestoresBothOriginalLocations() throws {
        let fixture = try Fixture(locationKey: "location-screenshot")
        defer { fixture.remove() }
        let oldBackup = Data(#"{"location":"/Volumes/Original","showThumbnail":true}"#.utf8)
        fixture.backup.set(oldBackup, forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings)
        fixture.backup.set(true, forKey: UserDefaults.Key.screenshotsCaptureEnabled)
        fixture.domain.set(fixture.folder.path, forKey: "location")
        fixture.domain.set("/Volumes/ModernOriginal", forKey: "location-screenshot")
        fixture.domain.set(false, forKey: "show-thumbnail")
        try fixture.preferences.enable()
        #expect(fixture.domain.value(forKey: "location-screenshot") as? String == fixture.folder.path)
        try fixture.preferences.disable()
        #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Original")
        #expect(fixture.domain.value(forKey: "location-screenshot") as? String == "/Volumes/ModernOriginal")
        #expect(fixture.domain.value(forKey: "show-thumbnail") as? Bool == true)
    }

    @Test func modernReapplyPreservesOriginallyAbsentLocation() throws {
        let fixture = try Fixture(["location": "/Volumes/Legacy"], locationKey: "location-screenshot")
        defer { fixture.remove() }
        try fixture.preferences.enable()
        try fixture.preferences.enable()
        try fixture.preferences.disable()
        #expect(fixture.domain.value(forKey: "location-screenshot") == nil)
        #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Legacy")
    }

    @Test func failedModernMigrationRestoresOriginalBackupBytes() throws {
        let fixture = try Fixture(locationKey: "location-screenshot")
        defer { fixture.remove() }
        let oldBackup = Data(#"{"location":"/Volumes/Original","showThumbnail":true}"#.utf8)
        fixture.backup.set(oldBackup, forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings)
        fixture.backup.set(true, forKey: UserDefaults.Key.screenshotsCaptureEnabled)
        fixture.domain.set(fixture.folder.path, forKey: "location")
        fixture.domain.set("/Volumes/ModernOriginal", forKey: "location-screenshot")
        fixture.domain.set(false, forKey: "show-thumbnail")
        fixture.domain.synchronizeResult = false
        #expect(throws: ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey)) { try fixture.preferences.enable() }
        #expect(fixture.backup.value(forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings) as? Data == oldBackup)
        #expect(fixture.domain.value(forKey: "location") as? String == fixture.folder.path)
        #expect(fixture.domain.value(forKey: "location-screenshot") as? String == "/Volumes/ModernOriginal")
        #expect(fixture.domain.value(forKey: "show-thumbnail") as? Bool == false)
        #expect(fixture.preferences.isEnabled)
    }

    @Test func modernDisablePreservesExternalEffectiveLocation() throws {
        let fixture = try Fixture(["location": "/Volumes/Legacy", "location-screenshot": "/Volumes/Original"], locationKey: "location-screenshot")
        defer { fixture.remove() }
        try fixture.preferences.enable()
        fixture.domain.set(fixture.folder.path, forKey: "location")
        fixture.domain.set("/Volumes/External", forKey: "location-screenshot")
        try fixture.preferences.disable()
        #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Legacy")
        #expect(fixture.domain.value(forKey: "location-screenshot") as? String == "/Volumes/External")
    }

    @Test func modernDisableWithoutBackupClearsBothOwnedLocations() throws {
        let fixture = try Fixture(locationKey: "location-screenshot")
        defer { fixture.remove() }
        fixture.domain.set(fixture.folder.path, forKey: "location")
        fixture.domain.set(fixture.folder.path, forKey: "location-screenshot")
        fixture.domain.set(false, forKey: "show-thumbnail")
        fixture.backup.set(true, forKey: UserDefaults.Key.screenshotsCaptureEnabled)
        try fixture.preferences.disable()
        #expect(fixture.domain.keys.isEmpty)
        #expect(fixture.preferences.isEnabled == false)
    }

    @Test func modernEnableFailureRestoresBothOriginalLocations() throws {
        let fixture = try Fixture(["location": "/Volumes/Legacy", "location-screenshot": "/Volumes/Current", "show-thumbnail": true], locationKey: "location-screenshot")
        defer { fixture.remove() }
        fixture.domain.synchronizeResult = false
        #expect(throws: ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey)) { try fixture.preferences.enable() }
        #expect(fixture.domain.value(forKey: "location") as? String == "/Volumes/Legacy")
        #expect(fixture.domain.value(forKey: "location-screenshot") as? String == "/Volumes/Current")
        #expect(fixture.domain.value(forKey: "show-thumbnail") as? Bool == true)
        #expect(fixture.backup.keys.isEmpty)
        #expect(fixture.preferences.isEnabled == false)
    }

    @Test func statusIsChangedElsewhereWhenLocationNoLongerMatches() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try fixture.preferences.enable()
        fixture.domain.set(fixture.folder.path + "/", forKey: "location")
        #expect(fixture.preferences.status(enabledFlag: true) == .active)
        fixture.domain.set("/Users/example/Documents", forKey: "location")
        #expect(fixture.preferences.status(enabledFlag: true) == .changedElsewhere)
        fixture.domain.set(nil, forKey: "location")
        #expect(fixture.preferences.status(enabledFlag: true) == .changedElsewhere)
        #expect(fixture.preferences.status(enabledFlag: false) == .disabled)
    }

    @Test func disableDoesNotOverwriteValuesTheUserChangedElsewhere() throws {
        let fixture = try Fixture(["location": "/Users/example/Desktop", "show-thumbnail": true]); defer { fixture.remove() }
        try fixture.preferences.enable()
        fixture.domain.set("/Users/example/Documents", forKey: "location")
        try fixture.preferences.disable()
        #expect(fixture.domain.value(forKey: "location") as? String == "/Users/example/Documents")
        #expect(fixture.domain.value(forKey: "show-thumbnail") as? Bool == true)
    }

    @Test func synchronizeFailureThrowsCaptureSettingsFailed() throws {
        let fixture = try Fixture(["location": "/Users/example/Desktop"]); defer { fixture.remove() }
        fixture.domain.synchronizeResult = false
        #expect(throws: ScreenshotFailure(key: "Screenshot Capture Settings Failed")) { try fixture.preferences.enable() }
        #expect(fixture.domain.value(forKey: "location") as? String == "/Users/example/Desktop")
        #expect(fixture.domain.value(forKey: "show-thumbnail") == nil)
        #expect(!fixture.preferences.isEnabled)
        fixture.domain.synchronizeResult = true
        try fixture.preferences.enable()
        fixture.domain.synchronizeResult = false
        #expect(throws: ScreenshotFailure(key: "Screenshot Capture Settings Failed")) { try fixture.preferences.disable() }
        #expect(fixture.preferences.isEnabled)
    }

    @Test func enableCreatesTheFolderBeforeRedirecting() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.path))
        try fixture.preferences.enable()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: fixture.folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test func onlyTabVisibilityIsExportable() {
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.showScreenshotsTab))
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.screenshotsCaptureEnabled))
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.screenshotsPreviousCaptureSettings))
    }
}
#endif
