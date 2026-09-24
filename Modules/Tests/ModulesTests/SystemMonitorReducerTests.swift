import SystemMonitor
import Testing

struct SystemMonitorReducerTests {
    @Test func formatsNetworkRateUsingBinaryUnits() {
        #expect(SystemMonitorFormatter.rate(bytesPerSecond: 1_536) == "1.5 KB/s")
    }

    @Test func disabledMenuBarMetricsDoNotNeedBackgroundSampling() {
        #expect(SystemMonitorPreferences(menuBarMetrics: []).requiresBackgroundSampling == false)
    }

    @Test func historyRetainsTheMostRecentSixtySnapshots() {
        var history = SystemMonitorHistory()

        for second in 0 ... 60 {
            history.append(SystemMonitorSnapshot(timestamp: Date(timeIntervalSinceReferenceDate: Double(second))))
        }

        #expect(history.snapshots.count == 60)
        #expect(history.snapshots.first?.timestamp == Date(timeIntervalSinceReferenceDate: 1))
    }
}
