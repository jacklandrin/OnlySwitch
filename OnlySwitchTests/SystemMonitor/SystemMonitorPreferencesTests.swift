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

    @Test
    @MainActor
    func preferencesRoundTripAndPublishChanges() throws {
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

        var received: SystemMonitorPreferences?
        let observer = NotificationCenter.default.addObserver(
            forName: .systemMonitorPreferencesChanged,
            object: nil,
            queue: .main
        ) { notification in
            received = notification.object as? SystemMonitorPreferences
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let expected = SystemMonitorPreferences(
            enabledPanelMetrics: [.cpu, .memory, .network],
            menuBarMetrics: [.cpu, .network],
            refreshInterval: 2
        )
        Preferences.shared.systemMonitorPreferences = expected

        #expect(Preferences.shared.systemMonitorPreferences == expected)
        #expect(received == expected)

        let data = try #require(defaults.data(forKey: key))
        let stored = try JSONDecoder().decode(StoredSystemMonitorPreferences.self, from: data)
        #expect(stored.version == StoredSystemMonitorPreferences.currentVersion)
        #expect(stored.historyPointCount == SystemMonitorHistory.maximumSampleCount)
        #expect(stored.preferences == expected)
    }
}
