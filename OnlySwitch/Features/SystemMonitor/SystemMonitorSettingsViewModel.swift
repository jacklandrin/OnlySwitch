import SwiftUI
import SystemMonitor

@MainActor
final class SystemMonitorSettingsViewModel: ObservableObject {
    @Published private(set) var preferences: SystemMonitorPreferences

    init(preferences: SystemMonitorPreferences = Preferences.shared.systemMonitorPreferences) {
        self.preferences = preferences
    }

    func panelMetricBinding(for metric: SystemMonitorMetric) -> Binding<Bool> {
        Binding(
            get: { self.preferences.enabledPanelMetrics.contains(metric) },
            set: { self.setPanelMetric(metric, isEnabled: $0) }
        )
    }

    func menuBarMetricBinding(for metric: SystemMonitorMetric) -> Binding<Bool> {
        Binding(
            get: { self.preferences.menuBarMetrics.contains(metric) },
            set: { self.setMenuBarMetric(metric, isEnabled: $0) }
        )
    }

    private func setPanelMetric(_ metric: SystemMonitorMetric, isEnabled: Bool) {
        updatePreferences { preferences in
            if isEnabled {
                preferences.enabledPanelMetrics.insert(metric)
            } else {
                preferences.enabledPanelMetrics.remove(metric)
            }
        }
    }

    private func setMenuBarMetric(_ metric: SystemMonitorMetric, isEnabled: Bool) {
        updatePreferences { preferences in
            if isEnabled {
                preferences.menuBarMetrics.insert(metric)
            } else {
                preferences.menuBarMetrics.remove(metric)
            }
        }
    }

    private func updatePreferences(_ update: (inout SystemMonitorPreferences) -> Void) {
        var updated = preferences
        update(&updated)
        preferences = updated
        Preferences.shared.systemMonitorPreferences = updated
    }
}
