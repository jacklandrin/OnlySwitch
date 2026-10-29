#if os(macOS)
import CoreFoundation
import Extensions
import Foundation

/// Minimal key/value preference store so the system-settings effect can be replaced in tests.
public protocol PreferenceDomain: Sendable {
    func value(forKey key: String) -> Any?
    /// nil removes the key.
    func set(_ value: Any?, forKey key: String)
    func synchronize() -> Bool
}

/// Live `CFPreferences` adapter for another application's domain (here `com.apple.screencapture`).
public struct CFPreferenceDomain: PreferenceDomain {
    public let applicationID: String
    public init(applicationID: String) { self.applicationID = applicationID }
    public func value(forKey key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, applicationID as CFString) }
    public func set(_ value: Any?, forKey key: String) {
        CFPreferencesSetAppValue(key as CFString, value.map { $0 as AnyObject as CFPropertyList }, applicationID as CFString)
    }
    public func synchronize() -> Bool { CFPreferencesAppSynchronize(applicationID as CFString) }
}

/// Live backup store: OnlySwitch's own `UserDefaults.standard`.
public struct StandardUserDefaultsDomain: PreferenceDomain {
    public init() {}
    public func value(forKey key: String) -> Any? { UserDefaults.standard.object(forKey: key) }
    public func set(_ value: Any?, forKey key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
    public func synchronize() -> Bool { true }
}

/// Opt-in takeover of the system screenshot settings: redirects the save location to the OnlySwitch folder and
/// hides the floating thumbnail, backing up the previous values once so `disable()` can restore them exactly.
public struct ScreenCapturePreferences: Sendable {
    static let locationKey = "location"
    static let screenshotLocationKey = "location-screenshot"
    static let showThumbnailKey = "show-thumbnail"
    private let domain: any PreferenceDomain
    private let backup: any PreferenceDomain
    private let folder: URL
    private let activeLocationKey: String

    public init(domain: any PreferenceDomain, backup: any PreferenceDomain, folder: URL, locationKey: String? = nil) {
        self.domain = domain
        self.backup = backup
        self.folder = folder
        if let locationKey {
            activeLocationKey = locationKey
        } else if #available(macOS 27, *) {
            activeLocationKey = Self.screenshotLocationKey
        } else {
            activeLocationKey = Self.locationKey
        }
    }

    public static func live(folder: URL) -> Self {
        Self(domain: CFPreferenceDomain(applicationID: "com.apple.screencapture"), backup: StandardUserDefaultsDomain(), folder: folder)
    }

    public var isEnabled: Bool { backup.value(forKey: UserDefaults.Key.screenshotsCaptureEnabled) as? Bool == true }

    public func status(enabledFlag: Bool) -> ScreenshotCaptureStatus {
        guard enabledFlag else { return .disabled }
        return isOurLocation(domain.value(forKey: activeLocationKey)) ? .active : .changedElsewhere
    }

    /// Backs up current values once, then writes the active destination and show-thumbnail = false. On a failed
    /// synchronize the domain is reverted and nothing is marked enabled.
    public func enable() throws {
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { throw ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey) }
        let current = currentSettings()
        let originalBackup = backup.value(forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings)
        var previous = storedBackup() ?? current
        if previous.screenshotLocationBackedUp != true {
            // Older backups never took ownership of this key. Preserve its current value before reapplying.
            previous.screenshotLocation = current.screenshotLocation
            previous.screenshotLocationBackedUp = true
        }
        guard let data = try? JSONEncoder().encode(previous) else { throw ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey) }
        backup.set(data, forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings)
        domain.set(folder.path, forKey: activeLocationKey)
        domain.set(false, forKey: Self.showThumbnailKey)
        guard domain.synchronize() else {
            write(current)
            _ = domain.synchronize()
            backup.set(originalBackup, forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings)
            throw ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey)
        }
        backup.set(true, forKey: UserDefaults.Key.screenshotsCaptureEnabled)
    }

    /// Restores the backup exactly (keys absent before are removed) and clears it. A value the user changed
    /// elsewhere after enabling is left alone. On a failed synchronize the backup is kept for a retry.
    public func disable() throws {
        // A lost or corrupt backup falls back to the system defaults (keys absent) rather than leaving
        // captures redirected to the OnlySwitch folder.
        let previous = storedBackup() ?? (isEnabled ? ScreenshotCaptureSettings(location: nil, showThumbnail: nil) : nil)
        if let previous {
            if isOurLocation(domain.value(forKey: Self.locationKey)) { domain.set(previous.location, forKey: Self.locationKey) }
            if previous.screenshotLocationBackedUp == true, isOurLocation(domain.value(forKey: Self.screenshotLocationKey)) {
                domain.set(previous.screenshotLocation, forKey: Self.screenshotLocationKey)
            }
            if domain.value(forKey: Self.showThumbnailKey) as? Bool == false { domain.set(previous.showThumbnail, forKey: Self.showThumbnailKey) }
            guard domain.synchronize() else { throw ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey) }
        }
        backup.set(nil, forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings)
        backup.set(nil, forKey: UserDefaults.Key.screenshotsCaptureEnabled)
    }

    // MARK: - Private

    private func currentSettings() -> ScreenshotCaptureSettings {
        ScreenshotCaptureSettings(location: domain.value(forKey: Self.locationKey) as? String, screenshotLocation: domain.value(forKey: Self.screenshotLocationKey) as? String, showThumbnail: domain.value(forKey: Self.showThumbnailKey) as? Bool)
    }

    private func write(_ settings: ScreenshotCaptureSettings) {
        domain.set(settings.location, forKey: Self.locationKey)
        domain.set(settings.screenshotLocation, forKey: Self.screenshotLocationKey)
        domain.set(settings.showThumbnail, forKey: Self.showThumbnailKey)
    }

    private func storedBackup() -> ScreenshotCaptureSettings? {
        (backup.value(forKey: UserDefaults.Key.screenshotsPreviousCaptureSettings) as? Data).flatMap { try? JSONDecoder().decode(ScreenshotCaptureSettings.self, from: $0) }
    }

    /// Compares after tilde expansion, standardization and trailing-slash normalisation.
    private func isOurLocation(_ value: Any?) -> Bool {
        guard let path = value as? String, !path.isEmpty else { return false }
        return Self.normalized(path) == Self.normalized(folder.path)
    }

    static func normalized(_ path: String) -> String {
        var result = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
#endif
