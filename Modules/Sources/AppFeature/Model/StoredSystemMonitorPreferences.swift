import Foundation
import SystemMonitor

struct StoredSystemMonitorPreferences: Codable {
    static let currentVersion = 1

    let version: Int
    let historyPointCount: Int
    let preferences: SystemMonitorPreferences

    init(preferences: SystemMonitorPreferences) {
        self.version = Self.currentVersion
        self.historyPointCount = SystemMonitorHistory.maximumSampleCount
        self.preferences = preferences
    }
}
