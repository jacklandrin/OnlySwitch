import Foundation
import SystemMonitor
import Testing
@testable import OnlySwitch

@Suite(.serialized)
struct SystemMonitorPreferencesTests {
    @Test
    func legacyPreferencesDecodeWithCompactModeDisabled() throws {
        let data = Data(#"{"enabledPanelMetrics":["cpu","memory"],"menuBarMetrics":["network"],"refreshInterval":2}"#.utf8)
        let preferences = try JSONDecoder().decode(SystemMonitorPreferences.self, from: data)

        #expect(preferences.isCompactMode == false)
        #expect(preferences.enabledPanelMetrics == [.cpu, .memory])
        #expect(preferences.menuBarMetrics == [.network])
        #expect(preferences.refreshInterval == 2)
    }

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
            refreshInterval: 2,
            isCompactMode: true
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

    @Test
    @MainActor
    func settingsBindingsPreserveCompactModeAndMetricChoices() {
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

        let viewModel = SystemMonitorSettingsViewModel(preferences: .init(
            enabledPanelMetrics: [.cpu, .network],
            menuBarMetrics: [.network],
            refreshInterval: 3
        ))
        viewModel.compactModeBinding.wrappedValue = true
        #expect(Preferences.shared.systemMonitorPreferences.isCompactMode)
        #expect(viewModel.preferences.enabledPanelMetrics == [.cpu, .network])
        #expect(viewModel.preferences.menuBarMetrics == [.network])

        viewModel.panelMetricBinding(for: .memory).wrappedValue = true
        viewModel.menuBarMetricBinding(for: .cpu).wrappedValue = true
        #expect(Preferences.shared.systemMonitorPreferences.isCompactMode)
        #expect(Preferences.shared.systemMonitorPreferences.enabledPanelMetrics == [.cpu, .memory, .network])
        #expect(Preferences.shared.systemMonitorPreferences.menuBarMetrics == [.cpu, .network])
        #expect(Preferences.shared.systemMonitorPreferences.refreshInterval == 3)

        viewModel.compactModeBinding.wrappedValue = false
        #expect(Preferences.shared.systemMonitorPreferences.isCompactMode == false)
        #expect(Preferences.shared.systemMonitorPreferences.enabledPanelMetrics == [.cpu, .memory, .network])
    }
}
