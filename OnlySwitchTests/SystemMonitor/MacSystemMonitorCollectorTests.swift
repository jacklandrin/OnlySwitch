import Darwin
import Dispatch
import SystemMonitor
import Testing
@testable import OnlySwitch

struct MacSystemMonitorCollectorTests {
    @Test
    func resetNetworkCounterProducesZeroRate() {
        #expect(NetworkRate.delta(current: 20, previous: 40, seconds: 1) == 0)
    }

    @Test
    func networkCountersUseOnlyOneLinkLayerEntryPerActiveInterface() {
        var seenNames = Set<String>()

        #expect(NetworkInterfaceFilter.shouldInclude(
            family: sa_family_t(AF_INET),
            flags: UInt32(IFF_UP),
            name: "en0",
            seenNames: &seenNames
        ) == false)
        #expect(NetworkInterfaceFilter.shouldInclude(
            family: sa_family_t(AF_LINK),
            flags: UInt32(IFF_UP),
            name: "en0",
            seenNames: &seenNames
        ))
        #expect(NetworkInterfaceFilter.shouldInclude(
            family: sa_family_t(AF_LINK),
            flags: UInt32(IFF_UP),
            name: "en0",
            seenNames: &seenNames
        ) == false)
    }

    @Test(arguments: [
        (DispatchSource.MemoryPressureEvent.normal, SystemMonitorMemoryPressure.normal),
        (DispatchSource.MemoryPressureEvent.warning, SystemMonitorMemoryPressure.warning),
        (DispatchSource.MemoryPressureEvent.critical, SystemMonitorMemoryPressure.critical)
    ])
    func memoryPressureEventsMapToStatus(
        event: DispatchSource.MemoryPressureEvent,
        expected: SystemMonitorMemoryPressure
    ) {
        #expect(MemoryPressureSampler.status(for: event) == expected)
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
    func firstSampleIncludesRealProcessRows() async {
        let collector = MacSystemMonitorCollector()
        let snapshot = await collector.sample()

        #expect(snapshot.processes.isEmpty == false)
        #expect(snapshot.processes.allSatisfy { process in
            process.pid > 0 && process.name.isEmpty == false && process.memoryBytes.value != nil
        })
    }

    @Test
    func privateGPUReadingsAreEitherUnavailableOrSane() async {
        let collector = MacSystemMonitorCollector()
        let snapshot = await collector.sample()

        #expect(snapshot.gpuUsage.value.map { $0 >= 0 && $0 <= 1 } ?? true)
        #expect(snapshot.gpuTemperatureCelsius.value.map { $0 > 1 && $0 < 125 } ?? true)
        #expect(snapshot.cpuTemperatureCelsius == .unavailable)
        #expect(snapshot.disks.allSatisfy { $0.temperatureCelsius == .unavailable })
    }

    @Test
    func hardwareIdentityKeepsUnavailableGPUCoreCountDistinctFromZero() async {
        let collector = MacSystemMonitorCollector()
        let snapshot = await collector.sample()

        #expect(snapshot.hardware.gpu.physicalCoreCount.value.map { $0 > 0 } ?? true)
        #expect(snapshot.hardware.gpu.logicalCoreCount == .unavailable)
        #expect(snapshot.hardware.cpu.physicalCoreCount.value.map { $0 > 0 } ?? true)
        #expect(snapshot.memory.value.map { $0.usage >= 0 && $0.usage <= 1 } ?? true)
    }
}
