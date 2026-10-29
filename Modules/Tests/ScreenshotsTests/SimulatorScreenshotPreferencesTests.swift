#if os(macOS)
import Extensions
import Foundation
import Testing
@testable import Screenshots

struct SimulatorScreenshotPreferencesTests {
    struct Fixture {
        let root: URL
        let domain: InMemoryPreferenceDomain
        let backup = InMemoryPreferenceDomain()
        var folder: URL { root.appendingPathComponent("OnlySwitch Screenshots", isDirectory: true) }
        init(_ values: [String: Any] = [:]) throws {
            root = try makeTemporaryDirectory()
            domain = InMemoryPreferenceDomain(values)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        var preferences: SimulatorScreenshotPreferences { SimulatorScreenshotPreferences(domain: domain, backup: backup, folder: folder) }
        var location: String? { domain.value(forKey: "ScreenShotSaveLocation") as? String }
    }

    @Test func enableBacksUpAndRedirectsSaveLocation() throws {
        let fixture = try Fixture(["ScreenShotSaveLocation": "/Users/example/Shots"]); defer { fixture.remove() }
        try fixture.preferences.enable()
        #expect(fixture.location == fixture.folder.path)
        #expect(fixture.preferences.isEnabled)
        try fixture.preferences.disable()
        #expect(fixture.location == "/Users/example/Shots")
        #expect(!fixture.preferences.isEnabled)
    }

    @Test func disableRemovesKeyThatWasAbsentBefore() throws {
        let fixture = try Fixture(["ConnectHardwareKeyboard": true]); defer { fixture.remove() }
        try fixture.preferences.enable()
        try fixture.preferences.disable()
        #expect(fixture.domain.keys == ["ConnectHardwareKeyboard"])
        #expect(fixture.backup.value(forKey: UserDefaults.Key.screenshotsPreviousSimulatorLocation) == nil)
    }

    @Test func enablingTwiceKeepsTheOriginalBackup() throws {
        let fixture = try Fixture(["ScreenShotSaveLocation": "/Volumes/Shots"]); defer { fixture.remove() }
        try fixture.preferences.enable()
        try fixture.preferences.enable()
        try fixture.preferences.disable()
        #expect(fixture.location == "/Volumes/Shots")
    }

    @Test func disableLeavesLocationChangedElsewhereAlone() throws {
        let fixture = try Fixture(["ScreenShotSaveLocation": "/Volumes/Old"]); defer { fixture.remove() }
        try fixture.preferences.enable()
        fixture.domain.set("/Volumes/Chosen", forKey: "ScreenShotSaveLocation")
        try fixture.preferences.disable()
        #expect(fixture.location == "/Volumes/Chosen")
        #expect(!fixture.preferences.isEnabled)
    }

    @Test func disableWithoutBackupRemovesOurLocation() throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        fixture.domain.set(fixture.folder.path + "/", forKey: "ScreenShotSaveLocation")
        try fixture.preferences.disable()
        #expect(fixture.domain.keys.isEmpty)
    }

    @Test func failedSynchronizeOnEnableRevertsAndThrows() throws {
        let fixture = try Fixture(["ScreenShotSaveLocation": "/Volumes/Old"]); defer { fixture.remove() }
        fixture.domain.synchronizeResult = false
        #expect(throws: ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey)) { try fixture.preferences.enable() }
        #expect(fixture.location == "/Volumes/Old")
        #expect(!fixture.preferences.isEnabled)
    }

    @Test func failedSynchronizeOnDisableKeepsBackupForRetry() throws {
        let fixture = try Fixture(["ScreenShotSaveLocation": "/Volumes/Old"]); defer { fixture.remove() }
        try fixture.preferences.enable()
        fixture.domain.synchronizeResult = false
        #expect(throws: ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey)) { try fixture.preferences.disable() }
        #expect(fixture.preferences.isEnabled)
        fixture.domain.synchronizeResult = true
        try fixture.preferences.disable()
        #expect(fixture.location == "/Volumes/Old")
    }
}
#endif
