#if os(macOS)
import Extensions
import Foundation

/// Opt-in takeover of the iOS Simulator screenshot save location (`com.apple.iphonesimulator`), paired with
/// `ScreenCapturePreferences`. The previous value is backed up once so `disable()` can restore it exactly.
public struct SimulatorScreenshotPreferences: Sendable {
    static let locationKey = "ScreenShotSaveLocation"
    private struct Backup: Codable { var location: String? }
    private let domain: any PreferenceDomain
    private let backup: any PreferenceDomain
    private let folder: URL

    public init(domain: any PreferenceDomain, backup: any PreferenceDomain, folder: URL) {
        self.domain = domain
        self.backup = backup
        self.folder = folder
    }

    public static func live(folder: URL) -> Self {
        Self(domain: CFPreferenceDomain(applicationID: "com.apple.iphonesimulator"), backup: StandardUserDefaultsDomain(), folder: folder)
    }

    /// True while a backup exists, i.e. the location was redirected and not yet restored.
    public var isEnabled: Bool { storedBackup() != nil }

    /// Backs up the current value once, then writes the OnlySwitch folder. On a failed synchronize the domain and
    /// backup are reverted.
    public func enable() throws {
        let current = domain.value(forKey: Self.locationKey) as? String
        let originalBackup = backup.value(forKey: UserDefaults.Key.screenshotsPreviousSimulatorLocation)
        if storedBackup() == nil {
            // Already pointing at our folder without a backup: treat the system default as the original.
            let previous = Backup(location: isOurLocation(current) ? nil : current)
            guard let data = try? JSONEncoder().encode(previous) else { throw ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey) }
            backup.set(data, forKey: UserDefaults.Key.screenshotsPreviousSimulatorLocation)
        }
        domain.set(folder.path, forKey: Self.locationKey)
        guard domain.synchronize() else {
            domain.set(current, forKey: Self.locationKey)
            _ = domain.synchronize()
            backup.set(originalBackup, forKey: UserDefaults.Key.screenshotsPreviousSimulatorLocation)
            throw ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey)
        }
    }

    /// Restores the backup (an absent key is removed) and clears it. A location changed elsewhere after enabling is
    /// left alone. Without a backup, a location still pointing at our folder falls back to the system default.
    /// On a failed synchronize the backup is kept for a retry.
    public func disable() throws {
        if isOurLocation(domain.value(forKey: Self.locationKey)) {
            domain.set(storedBackup()?.location, forKey: Self.locationKey)
            guard domain.synchronize() else { throw ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey) }
        }
        backup.set(nil, forKey: UserDefaults.Key.screenshotsPreviousSimulatorLocation)
    }

    // MARK: - Private

    private func storedBackup() -> Backup? {
        (backup.value(forKey: UserDefaults.Key.screenshotsPreviousSimulatorLocation) as? Data).flatMap { try? JSONDecoder().decode(Backup.self, from: $0) }
    }

    private func isOurLocation(_ value: Any?) -> Bool {
        guard let path = value as? String, !path.isEmpty else { return false }
        return ScreenCapturePreferences.normalized(path) == ScreenCapturePreferences.normalized(folder.path)
    }
}
#endif
