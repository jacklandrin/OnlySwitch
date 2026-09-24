import Foundation
import SystemMonitor
import Testing
@testable import OnlySwitch

struct SystemMonitorPreferencesTests {
    @Test
    @MainActor
    func invalidIntervalFallsBackToOneSecond() {
        let defaults = UserDefaults.standard
        let key = UserDefaults.Key.systemMonitorPreferences
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(Data("malformed".utf8), forKey: key)

        #expect(SystemMonitorPreferences(refreshInterval: 0).refreshInterval == 1)
        #expect(Preferences.shared.systemMonitorPreferences.refreshInterval == 1)
    }
}
