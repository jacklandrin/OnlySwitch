import Darwin
import Dispatch
import Foundation
import IOKit
import Metal
import SystemMonitor

/// Calculates a non-negative network rate from two monotonic interface counters.
///
/// Counter resets occur when an interface is re-created, so they intentionally produce zero
/// rather than a misleading burst.
enum NetworkRate {
    static func delta(current: UInt64, previous: UInt64?, seconds: TimeInterval) -> Double {
        guard let previous, current >= previous, seconds > 0 else { return 0 }
        return Double(current - previous) / seconds
    }
}

enum ProcessSampler {
    static func topRows(from rows: [SystemMonitorProcess], limit: Int) -> [SystemMonitorProcess] {
        guard limit > 0 else { return [] }

        return rows
            .sorted {
                let lhsUsage = $0.cpuUsage.value ?? 0
                let rhsUsage = $1.cpuUsage.value ?? 0
                if lhsUsage == rhsUsage {
                    return $0.pid < $1.pid
                }
                return lhsUsage > rhsUsage
            }
            .prefix(limit)
            .map { $0 }
    }
}

enum NetworkInterfaceFilter {
    static func shouldInclude(
        family: sa_family_t,
        flags: UInt32,
        name: String,
        seenNames: inout Set<String>
    ) -> Bool {
        guard family == sa_family_t(AF_LINK),
              (flags & UInt32(IFF_UP)) != 0,
              (flags & UInt32(IFF_LOOPBACK)) == 0
        else { return false }
        return seenNames.insert(name).inserted
    }
}

enum MemoryPressureSampler {
    static func status(
        for event: DispatchSource.MemoryPressureEvent
    ) -> SystemMonitorMemoryPressure {
        if event.contains(.critical) { return .critical }
        if event.contains(.warning) { return .warning }
        return .normal
    }
}

/// Reads Apple Silicon GPU counters exposed through undocumented IOKit services.
///
/// `AGXAccelerator`'s `PerformanceStatistics`, `gpu-core-count`, and the AppleSMC user client
/// are implementation details rather than supported macOS APIs. They are intentionally confined
/// to this type, only used on Apple Silicon, and treated as optional so an OS or hardware change
/// cannot affect monitor availability or process stability. This path is unsuitable for Mac App
/// Store distribution without separately validating Apple's current review policy.
private struct PrivateAppleSiliconGPUReader {
    struct Reading {
        let usage: Double?
        let temperatureCelsius: Double?
    }

    private static let maximumSensorKeys = 4_096
    private var smcConnection: io_connect_t = IO_OBJECT_NULL
    private var gpuTemperatureKeys: [UInt32]?

    mutating func sample() -> Reading {
        guard Self.isAppleSilicon else { return Reading(usage: nil, temperatureCelsius: nil) }
        return Reading(
            usage: Self.readUsage(),
            temperatureCelsius: readTemperature()
        )
    }

    mutating func close() {
        guard smcConnection != IO_OBJECT_NULL else { return }
        IOServiceClose(smcConnection)
        smcConnection = IO_OBJECT_NULL
        gpuTemperatureKeys = nil
    }

    static func coreCount() -> Int? {
        guard isAppleSilicon else { return nil }
        let coreCount: NSNumber? = withAccelerator { entry in
            guard let property = IORegistryEntryCreateCFProperty(
                entry,
                "gpu-core-count" as CFString,
                kCFAllocatorDefault,
                0
            ) else { return nil }
            return property.takeRetainedValue() as? NSNumber
        }
        guard let coreCount = coreCount?.intValue, coreCount > 0 else { return nil }
        return coreCount
    }

    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    private static func readUsage() -> Double? {
        withAccelerator { entry in
            guard let property = IORegistryEntryCreateCFProperty(
                entry,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            ), let statistics = property.takeRetainedValue() as? [String: Any],
            let utilization = statistics["Device Utilization %"] as? NSNumber
            else { return nil }

            let value = utilization.doubleValue / 100
            return value.isFinite ? min(max(value, 0), 1) : nil
        }
    }

    private static func withAccelerator<Value>(
        _ body: (io_registry_entry_t) -> Value?
    ) -> Value? {
        guard let matching = IOServiceMatching("AGXAccelerator") else { return nil }
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            if let value = body(entry) { return value }
        }
        return nil
    }

    private mutating func readTemperature() -> Double? {
        guard openSMCIfNeeded() else { return nil }
        if gpuTemperatureKeys == nil {
            gpuTemperatureKeys = discoverGPUTemperatureKeys()
        }
        guard let gpuTemperatureKeys else { return nil }
        return gpuTemperatureKeys
            .compactMap { readTemperature(key: $0) }
            .filter { $0 > 1 && $0 < 125 }
            .max()
    }

    private mutating func openSMCIfNeeded() -> Bool {
        if smcConnection != IO_OBJECT_NULL { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &smcConnection) == KERN_SUCCESS
    }

    private func discoverGPUTemperatureKeys() -> [UInt32] {
        guard let keyCount = readUnsignedInteger(key: Self.fourCharacterCode("#KEY")),
              keyCount > 0, keyCount <= Self.maximumSensorKeys
        else { return [] }

        return (0 ..< keyCount).compactMap { index in
            guard let key = key(at: index), Self.string(for: key).hasPrefix("Tg") else { return nil }
            return readTemperature(key: key) == nil ? nil : key
        }
    }

    private func key(at index: Int) -> UInt32? {
        var input = SMCParameter()
        input.data8 = SMCCommand.keyFromIndex.rawValue
        input.data32 = UInt32(index)
        guard let output = callSMC(&input), output.result == 0, output.key != 0 else { return nil }
        return output.key
    }

    private func readUnsignedInteger(key: UInt32) -> Int? {
        guard let data = readData(key: key), !data.isEmpty else { return nil }
        let value = data.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Int(value)
    }

    private func readTemperature(key: UInt32) -> Double? {
        guard let data = readData(key: key), data.count >= 2 else { return nil }
        // Apple Silicon temperature SMC keys are normally `sp78`; the first two bytes are a
        // signed 8.8 fixed-point Celsius reading. Reject implausible values at the caller.
        let raw = Int16(bitPattern: (UInt16(data[0]) << 8) | UInt16(data[1]))
        return Double(raw) / 256
    }

    private func readData(key: UInt32) -> [UInt8]? {
        var infoRequest = SMCParameter()
        infoRequest.key = key
        infoRequest.data8 = SMCCommand.keyInfo.rawValue
        guard let info = callSMC(&infoRequest), info.result == 0,
              info.keyInfo.dataSize > 0, info.keyInfo.dataSize <= 32
        else { return nil }

        var readRequest = SMCParameter()
        readRequest.key = key
        readRequest.keyInfo.dataSize = info.keyInfo.dataSize
        readRequest.data8 = SMCCommand.readKey.rawValue
        guard let value = callSMC(&readRequest), value.result == 0 else { return nil }

        return Array(value.bytes.prefix(Int(info.keyInfo.dataSize)))
    }

    private func callSMC(_ input: inout SMCParameter) -> SMCParameter? {
        guard smcConnection != IO_OBJECT_NULL,
              MemoryLayout<SMCParameter>.stride == 80
        else { return nil }
        var output = SMCParameter()
        var outputSize = MemoryLayout<SMCParameter>.stride
        let result = IOConnectCallStructMethod(
            smcConnection,
            UInt32(SMCCommand.handleEvent.rawValue),
            &input,
            MemoryLayout<SMCParameter>.stride,
            &output,
            &outputSize
        )
        guard result == KERN_SUCCESS, outputSize == MemoryLayout<SMCParameter>.stride else { return nil }
        return output
    }

    private static func fourCharacterCode(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func string(for value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    private enum SMCCommand: UInt8 {
        case handleEvent = 2
        case readKey = 5
        case keyFromIndex = 8
        case keyInfo = 9
    }

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPowerLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpu: UInt32 = 0
        var gpu: UInt32 = 0
        var memory: UInt32 = 0
    }

    private struct SMCKeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var attributes: UInt8 = 0
    }

    /// This memory layout is the private AppleSMC user-client ABI. The explicit two-byte field
    /// is required to retain its 80-byte C layout before passing it across the IOKit boundary.
    private struct SMCParameter {
        var key: UInt32 = 0
        var version = SMCVersion()
        var powerLimit = SMCPowerLimit()
        var keyInfo = SMCKeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var byte0: UInt8 = 0, byte1: UInt8 = 0, byte2: UInt8 = 0, byte3: UInt8 = 0
        var byte4: UInt8 = 0, byte5: UInt8 = 0, byte6: UInt8 = 0, byte7: UInt8 = 0
        var byte8: UInt8 = 0, byte9: UInt8 = 0, byte10: UInt8 = 0, byte11: UInt8 = 0
        var byte12: UInt8 = 0, byte13: UInt8 = 0, byte14: UInt8 = 0, byte15: UInt8 = 0
        var byte16: UInt8 = 0, byte17: UInt8 = 0, byte18: UInt8 = 0, byte19: UInt8 = 0
        var byte20: UInt8 = 0, byte21: UInt8 = 0, byte22: UInt8 = 0, byte23: UInt8 = 0
        var byte24: UInt8 = 0, byte25: UInt8 = 0, byte26: UInt8 = 0, byte27: UInt8 = 0
        var byte28: UInt8 = 0, byte29: UInt8 = 0, byte30: UInt8 = 0, byte31: UInt8 = 0

        var bytes: [UInt8] {
            withUnsafeBytes(of: self) { rawBuffer in
                Array(rawBuffer.suffix(32))
            }
        }
    }
}

/// Samples macOS system metrics.
///
/// This actor owns all mutable counters so rates cannot be computed from interleaved samples.
/// It uses a deliberately isolated, opt-in-by-platform private IOKit path for Apple Silicon GPU
/// metrics. If that path is absent or changes on a future macOS release, the affected values stay
/// explicitly unavailable.
actor MacSystemMonitorCollector {
    private struct CPUTicks {
        let busy: UInt64
        let total: UInt64
    }

    private struct NetworkCounters {
        let downloaded: UInt64
        let uploaded: UInt64
    }

    private struct ProcessCounters {
        let cpuNanoseconds: UInt64
        let residentBytes: UInt64
        let name: String
    }

    private var previousCPUTicks: CPUTicks?
    private var previousNetworkCounters: NetworkCounters?
    private var previousProcessCPUTimes: [Int32: UInt64] = [:]
    private var previousSampleUptime: TimeInterval?
    private var lastCollectedUptime: TimeInterval?
    private var latestSnapshot: SystemMonitorSnapshot?
    private var memoryPressure: SystemMonitorMemoryPressure = .normal
    private var privateGPUReader = PrivateAppleSiliconGPUReader()
    private let memoryPressureSource: any DispatchSourceMemoryPressure
    private let hardware: SystemMonitorHardware

    init() {
        hardware = Self.readHardware(gpuCoreCount: PrivateAppleSiliconGPUReader.coreCount())
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .global(qos: .utility))
        memoryPressureSource = source
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            let status = MemoryPressureSampler.status(for: source.data)
            Task { [weak self] in
                await self?.recordMemoryPressure(status)
            }
        }
        source.activate()
    }

    deinit {
        memoryPressureSource.cancel()
        privateGPUReader.close()
    }

    nonisolated static func liveClient(
        refreshInterval: TimeInterval = 1
    ) -> SystemMonitorClient {
        let collector = Self()
        return SystemMonitorClient {
            collector.snapshotStream(refreshInterval: refreshInterval)
        }
    }

    nonisolated func snapshotStream(
        refreshInterval: TimeInterval = 1
    ) -> AsyncThrowingStream<SystemMonitorSnapshot, Error> {
        let interval = max(refreshInterval, 1)

        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                while Task.isCancelled == false {
                    continuation.yield(await self.sample())

                    do {
                        try await Task.sleep(for: .seconds(interval))
                    } catch is CancellationError {
                        break
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func sample() -> SystemMonitorSnapshot {
        let uptime = ProcessInfo.processInfo.systemUptime
        if let lastCollectedUptime, let latestSnapshot, uptime - lastCollectedUptime < 1 {
            return latestSnapshot
        }

        let now = Date()
        let elapsed = previousSampleUptime.map { max(uptime - $0, 0) }

        let cpuUsage = readCPUTicks().map { current in
            defer { previousCPUTicks = current }
            guard let previous = previousCPUTicks, current.total >= previous.total else { return 0.0 }
            let totalDelta = current.total - previous.total
            guard totalDelta > 0, current.busy >= previous.busy else { return 0.0 }
            return min(max(Double(current.busy - previous.busy) / Double(totalDelta), 0), 1)
        }

        let network = readNetworkCounters().map { current in
            defer { previousNetworkCounters = current }
            let seconds = elapsed ?? 0
            return SystemMonitorNetwork(
                totalDownloadedBytes: current.downloaded,
                totalUploadedBytes: current.uploaded,
                downloadBytesPerSecond: NetworkRate.delta(
                    current: current.downloaded,
                    previous: previousNetworkCounters?.downloaded,
                    seconds: seconds
                ),
                uploadBytesPerSecond: NetworkRate.delta(
                    current: current.uploaded,
                    previous: previousNetworkCounters?.uploaded,
                    seconds: seconds
                )
            )
        }

        let processes = readProcesses(elapsed: elapsed ?? 0)

        let privateGPU = privateGPUReader.sample()
        let snapshot = SystemMonitorSnapshot(
            timestamp: now,
            cpuUsage: cpuUsage.map(MetricAvailability.available) ?? .unavailable,
            cpuTemperatureCelsius: .unavailable,
            gpuUsage: privateGPU.usage.map(MetricAvailability.available) ?? .unavailable,
            gpuTemperatureCelsius: privateGPU.temperatureCelsius.map(MetricAvailability.available) ?? .unavailable,
            hardware: hardware,
            memory: readMemory().map(MetricAvailability.available) ?? .unavailable,
            disks: readDisks(),
            network: network.map(MetricAvailability.available) ?? .unavailable,
            processes: ProcessSampler.topRows(from: processes, limit: 12)
        )
        previousSampleUptime = uptime
        lastCollectedUptime = uptime
        latestSnapshot = snapshot
        return snapshot
    }
}

private extension MacSystemMonitorCollector {
    static func readHardware(gpuCoreCount: Int?) -> SystemMonitorHardware {
        let gpuName = MTLCreateSystemDefaultDevice()?.name
        let cpuModel = readSysctlString("machdep.cpu.brand_string")
            ?? gpuName.flatMap { $0.hasPrefix("Apple ") ? $0 : nil }

        return SystemMonitorHardware(
            cpu: SystemMonitorProcessor(
                model: cpuModel.map(MetricAvailability.available) ?? .unavailable,
                physicalCoreCount: readSysctlInt("hw.physicalcpu").map(MetricAvailability.available) ?? .unavailable,
                logicalCoreCount: readSysctlInt("hw.logicalcpu").map(MetricAvailability.available) ?? .unavailable
            ),
            gpu: SystemMonitorProcessor(
                model: gpuName.map(MetricAvailability.available) ?? .unavailable,
                // `gpu-core-count` is an undocumented IORegistry property on Apple Silicon.
                // Do not infer a count from the chip name: unavailable is more honest on
                // unsupported hardware and future macOS releases.
                physicalCoreCount: gpuCoreCount.map(MetricAvailability.available) ?? .unavailable,
                logicalCoreCount: .unavailable
            )
        )
    }

    static func readSysctlString(_ name: String) -> String? {
        var byteCount = 0
        guard sysctlbyname(name, nil, &byteCount, nil, 0) == 0, byteCount > 1 else { return nil }

        var buffer = Array(repeating: CChar(0), count: byteCount)
        guard sysctlbyname(name, &buffer, &byteCount, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }

    static func readSysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var byteCount = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &byteCount, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }

    func recordMemoryPressure(_ status: SystemMonitorMemoryPressure) {
        memoryPressure = status
    }

    private func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(busy: user + system + nice, total: user + system + nice + idle)
    }

    func readMemory() -> SystemMonitorMemory? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let size = UInt64(pageSize)
        let active = UInt64(info.active_count) * size
        let wired = UInt64(info.wire_count) * size
        let compressed = UInt64(info.compressor_page_count) * size
        let cached = UInt64(info.external_page_count) * size

        return SystemMonitorMemory(
            totalBytes: UInt64(ProcessInfo.processInfo.physicalMemory),
            usedBytes: active + wired + compressed,
            compressedBytes: compressed,
            cachedBytes: cached,
            swapUsedBytes: readSwapUsedBytes(),
            pressure: .available(memoryPressure)
        )
    }

    func readSwapUsedBytes() -> UInt64 {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let status = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        return status == 0 ? UInt64(swapUsage.xsu_used) : 0
    }

    func readDisks() -> [SystemMonitorDisk] {
        let keys: Set<URLResourceKey> = [
            .nameKey,
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsLocalKey
        ]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumes.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsLocal == true,
                  let total = values.volumeTotalCapacity, total > 0,
                  let available = values.volumeAvailableCapacity
            else { return nil }

            let totalBytes = UInt64(total)
            let availableBytes = UInt64(max(available, 0))
            return SystemMonitorDisk(
                id: values.volumeUUIDString ?? url.path,
                name: values.volumeName ?? values.name ?? url.lastPathComponent,
                totalBytes: totalBytes,
                usedBytes: totalBytes >= availableBytes ? totalBytes - availableBytes : 0,
                temperatureCelsius: .unavailable
            )
        }
    }

    private func readNetworkCounters() -> NetworkCounters? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return nil }
        defer { freeifaddrs(firstInterface) }

        var seenNames = Set<String>()
        var downloaded: UInt64 = 0
        var uploaded: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            let flags = interface.pointee.ifa_flags
            guard let address = interface.pointee.ifa_addr,
                  let namePointer = interface.pointee.ifa_name,
                  let dataPointer = interface.pointee.ifa_data
            else { continue }

            let name = String(cString: namePointer)
            guard NetworkInterfaceFilter.shouldInclude(
                family: address.pointee.sa_family,
                flags: flags,
                name: name,
                seenNames: &seenNames
            ) else { continue }
            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            downloaded &+= UInt64(data.ifi_ibytes)
            uploaded &+= UInt64(data.ifi_obytes)
        }

        return NetworkCounters(downloaded: downloaded, uploaded: uploaded)
    }

    func readProcesses(elapsed: TimeInterval) -> [SystemMonitorProcess] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        let pidCount = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = Array(repeating: pid_t(), count: pidCount)
        let filledByteCount = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count))
        }
        guard filledByteCount > 0 else { return [] }

        let filledCount = Int(filledByteCount) / MemoryLayout<pid_t>.stride
        var currentCPUTimes: [Int32: UInt64] = [:]
        let rows = pids.prefix(filledCount).compactMap { pid -> SystemMonitorProcess? in
            guard pid > 0, let counters = processCounters(for: pid) else { return nil }
            let cpuUsage: Double
            if let previous = previousProcessCPUTimes[pid], counters.cpuNanoseconds >= previous, elapsed > 0 {
                cpuUsage = min(max(Double(counters.cpuNanoseconds - previous) / (elapsed * 1_000_000_000), 0), 1)
            } else {
                cpuUsage = 0
            }
            currentCPUTimes[pid] = counters.cpuNanoseconds
            return SystemMonitorProcess(
                pid: pid,
                name: counters.name,
                cpuUsage: .available(cpuUsage),
                memoryBytes: .available(counters.residentBytes),
                downloadBytesPerSecond: .unavailable,
                uploadBytesPerSecond: .unavailable
            )
        }
        previousProcessCPUTimes = currentCPUTimes
        return rows
    }

    private func processCounters(for pid: pid_t) -> ProcessCounters? {
        var usage = rusage_info_v2()
        let resourceUsageResult = OnlySwitchProcessRusageV2(pid, &usage)

        // `proc_pid_rusage` can be denied for individual processes (and has differed between
        // macOS releases for sandboxed callers). Use the documented task-info query as a
        // per-process fallback rather than dropping every row when that happens. Both sources
        // report cumulative CPU time and resident memory, so downstream rate calculations stay
        // identical.
        let values: (cpuNanoseconds: UInt64, residentBytes: UInt64)
        if resourceUsageResult == 0 {
            values = (
                cpuNanoseconds: usage.ri_user_time + usage.ri_system_time,
                residentBytes: usage.ri_resident_size
            )
        } else {
            var taskInfo = proc_taskinfo()
            let returnedByteCount = proc_pidinfo(
                pid,
                PROC_PIDTASKINFO,
                0,
                &taskInfo,
                Int32(MemoryLayout<proc_taskinfo>.size)
            )
            guard returnedByteCount == MemoryLayout<proc_taskinfo>.size else { return nil }
            values = (
                cpuNanoseconds: taskInfo.pti_total_user + taskInfo.pti_total_system,
                residentBytes: taskInfo.pti_resident_size
            )
        }

        var nameBuffer = Array(repeating: CChar(0), count: Int(MAXCOMLEN) + 1)
        let nameLength = nameBuffer.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return Int32(0) }
            return proc_name(pid, baseAddress, UInt32(buffer.count))
        }

        let name: String
        if nameLength > 0 {
            name = String(
                decoding: nameBuffer.prefix(Int(nameLength)).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
        } else {
            var pathBuffer = Array(repeating: CChar(0), count: Int(MAXPATHLEN) * 4)
            let pathLength = pathBuffer.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return Int32(0) }
                return proc_pidpath(pid, baseAddress, UInt32(buffer.count))
            }
            if pathLength > 0 {
                let executableName = URL(fileURLWithPath: String(cString: pathBuffer)).lastPathComponent
                name = executableName.isEmpty ? "Process \(pid)" : executableName
            } else {
                // Keep otherwise valid resource counters visible even when macOS withholds the
                // process name and path for a protected process.
                name = "Process \(pid)"
            }
        }

        return ProcessCounters(
            cpuNanoseconds: values.cpuNanoseconds,
            residentBytes: values.residentBytes,
            name: name
        )
    }
}
