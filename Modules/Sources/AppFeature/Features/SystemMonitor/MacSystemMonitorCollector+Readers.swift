import Darwin
import Foundation
import Metal
import SystemMonitor
import OnlySwitchObjC

extension MacSystemMonitorCollector {
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

    func readCPUTicks() -> CPUTicks? {
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

    func readNetworkCounters() -> NetworkCounters? {
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

    func readProcesses(
        elapsed: TimeInterval,
        previousProcessCPUTimes: inout [Int32: ProcessCPUBaseline],
        sampledProcessIdentities: inout [Int32: SystemMonitorProcessIdentity]
    ) -> [SystemMonitorProcess] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        let pidCount = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = Array(repeating: pid_t(), count: pidCount)
        let filledByteCount = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count))
        }
        guard filledByteCount > 0 else { return [] }

        let filledCount = Int(filledByteCount) / MemoryLayout<pid_t>.stride
        var currentCPUTimes: [Int32: ProcessCPUBaseline] = [:]
        let rows = pids.prefix(filledCount).compactMap { pid -> SystemMonitorProcess? in
            guard pid > 0, let counters = processCounters(for: pid) else { return nil }
            let cpuUsage: Double
            if let previous = previousProcessCPUTimes[pid],
               previous.identity == counters.identity,
               counters.cpuNanoseconds >= previous.cpuNanoseconds,
               elapsed > 0 {
                cpuUsage = min(max(Double(counters.cpuNanoseconds - previous.cpuNanoseconds) / (elapsed * 1_000_000_000), 0), 1)
            } else {
                cpuUsage = 0
            }
            currentCPUTimes[pid] = ProcessCPUBaseline(
                identity: counters.identity,
                cpuNanoseconds: counters.cpuNanoseconds
            )
            if let identity = counters.identity {
                sampledProcessIdentities[pid] = identity
            }
            return SystemMonitorProcess(
                pid: pid,
                name: counters.name,
                cpuUsage: .available(cpuUsage),
                memoryBytes: counters.memoryBytes.map { .available($0) } ?? .unavailable,
                downloadBytesPerSecond: .unavailable,
                uploadBytesPerSecond: .unavailable
            )
        }
        previousProcessCPUTimes = currentCPUTimes
        return rows
    }

    private func processCounters(for pid: pid_t) -> ProcessCounters? {
        let identity = SystemMonitorProcessActivation.processIdentity(pid: pid)
        var usage = rusage_info_v2()
        let resourceUsageResult = OnlySwitchProcessRusageV2(pid, &usage)

        // `proc_pid_rusage` can be denied for individual processes (and has differed between
        // macOS releases for sandboxed callers). Use the documented task-info query as a
        // per-process CPU fallback rather than dropping every row when that happens. Physical
        // footprint is not available from task info, and RSS is intentionally not substituted
        // because it measures different memory semantics.
        let values: (cpuNanoseconds: UInt64, memoryBytes: UInt64?)
        if resourceUsageResult == 0 {
            values = (
                cpuNanoseconds: usage.ri_user_time + usage.ri_system_time,
                memoryBytes: usage.ri_phys_footprint
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
                memoryBytes: nil
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
            memoryBytes: values.memoryBytes,
            name: name,
            identity: identity
        )
    }
}
