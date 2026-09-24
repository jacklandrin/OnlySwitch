import SystemMonitor
import Testing
@testable import OnlySwitch

struct MacSystemMonitorCollectorTests {
    @Test
    func resetNetworkCounterProducesZeroRate() {
        #expect(NetworkRate.delta(current: 20, previous: 40, seconds: 1) == 0)
    }

    @Test
    func processRowsAreSortedAndLimited() {
        let fixtures = (0 ..< 16).map { index in
            SystemMonitorProcess(
                pid: Int32(index + 1),
                name: "Process \(index + 1)",
                cpuUsage: .available(Double(index) / 100),
                memoryBytes: .available(UInt64(index))
            )
        }

        let rows = ProcessSampler.topRows(from: fixtures, limit: 12)

        #expect(rows.count == 12)
        #expect(rows.first?.pid == 16)
        #expect(rows.last?.pid == 5)
    }

    @Test
    func unavailableMetricsRemainExplicitlyUnavailable() async {
        let collector = MacSystemMonitorCollector()
        let snapshot = await collector.sample()

        #expect(snapshot.gpuUsage == .unavailable)
        #expect(snapshot.gpuTemperatureCelsius == .unavailable)
        #expect(snapshot.cpuTemperatureCelsius == .unavailable)
        #expect(snapshot.disks.allSatisfy { $0.temperatureCelsius == .unavailable })
    }
}
