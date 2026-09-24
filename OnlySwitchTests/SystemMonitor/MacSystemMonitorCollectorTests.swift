import Darwin
import Dispatch
import SystemMonitor
import Testing
@testable import OnlySwitch

struct MacSystemMonitorCollectorTests {
    @Test(arguments: [
        ("sp78", [UInt8(0x2E), 0x80], 46.5),
        ("sp78", [UInt8(0x15), 0x00], 21.0),
        ("flt ", [UInt8(0x00), 0x00, 0x3A, 0x42], 46.5)
    ])
    func temperatureCodecDecodesSupportedSMCPayloads(
        dataType: String,
        bytes: [UInt8],
        expectedCelsius: Double
    ) {
        let decoded = SMCTemperatureCodec.decode(
            dataType: fourCharacterCode(dataType),
            bytes: bytes
        )

        #expect(decoded == expectedCelsius)
    }

    @Test(arguments: [
        ("sp78", [UInt8(0x2E)]),
        ("flt ", [UInt8(0x00), 0x00, 0x3A]),
        ("ui32", [UInt8(0x00), 0x00, 0x00, 0x2E]),
        ("flt ", [UInt8(0x00), 0x00, 0x80, 0x7F]),
        ("flt ", [UInt8(0x00), 0x00, 0xC0, 0x7F])
    ])
    func temperatureCodecRejectsUnsupportedMalformedAndNonFinitePayloads(
        dataType: String,
        bytes: [UInt8]
    ) {
        let decoded = SMCTemperatureCodec.decode(
            dataType: fourCharacterCode(dataType),
            bytes: bytes
        )

        #expect(decoded == nil)
    }

    @Test(arguments: [
        (10.0, true),
        (124.9, true),
        (9.9, false),
        (125.0, false),
        (-1.0, false),
        (Double.infinity, false),
        (Double.nan, false)
    ])
    func temperaturePlausibilityBoundsPreventBogusSensorValues(
        celsius: Double,
        isPlausible: Bool
    ) {
        #expect(SMCTemperatureCodec.isPlausible(celsius) == isPlausible)
    }

    @Test
    func sensorKeySelectionKeepsCPUAndGPUClassesSeparate() {
        let cpuPerformance = fourCharacterCode("Tp0P")
        let cpuEfficiency = fourCharacterCode("Te0P")
        let m3CPU = fourCharacterCode("Tf04")
        let m3GPU = fourCharacterCode("Tf14")
        let gpu = fourCharacterCode("Tg0P")

        #expect(SMCTemperatureCodec.isCPUKey(cpuPerformance, chipModel: "Apple M4 Max"))
        #expect(SMCTemperatureCodec.isCPUKey(cpuEfficiency, chipModel: "Apple M4 Max"))
        #expect(SMCTemperatureCodec.isCPUKey(m3CPU, chipModel: "Apple M3 Max"))
        #expect(SMCTemperatureCodec.isCPUKey(m3GPU, chipModel: "Apple M3 Max") == false)
        #expect(SMCTemperatureCodec.isCPUKey(m3CPU, chipModel: "Apple M4 Max") == false)
        #expect(SMCTemperatureCodec.isCPUKey(gpu, chipModel: "Apple M4 Max") == false)
        #expect(SMCTemperatureCodec.isGPUKey(m3GPU, chipModel: "Apple M3 Max"))
        #expect(SMCTemperatureCodec.isGPUKey(m3CPU, chipModel: "Apple M3 Max") == false)
        #expect(SMCTemperatureCodec.isGPUKey(gpu, chipModel: "Apple M4 Max"))
        #expect(SMCTemperatureCodec.isGPUKey(cpuPerformance, chipModel: "Apple M4 Max") == false)
    }

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
        #expect(snapshot.gpuTemperatureCelsius.value.map { $0 >= 10 && $0 < 125 } ?? true)
        #expect(snapshot.cpuTemperatureCelsius.value.map { $0 >= 10 && $0 < 125 } ?? true)
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

    private func fourCharacterCode(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
