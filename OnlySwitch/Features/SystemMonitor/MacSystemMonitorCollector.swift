import Darwin
import Foundation
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

/// A public-API-only sampler for macOS system metrics.
///
/// This actor owns all mutable counters so rates cannot be computed from interleaved samples.
/// GPU usage and all temperatures have no supported public API, and are always represented as
/// unavailable rather than obtained through private frameworks, shell commands, or a helper.
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

        let snapshot = SystemMonitorSnapshot(
            timestamp: now,
            cpuUsage: cpuUsage.map(MetricAvailability.available) ?? .unavailable,
            cpuTemperatureCelsius: .unavailable,
            gpuUsage: .unavailable,
            gpuTemperatureCelsius: .unavailable,
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
            pressure: .unavailable
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
            guard (flags & UInt32(IFF_UP)) != 0, (flags & UInt32(IFF_LOOPBACK)) == 0,
                  let namePointer = interface.pointee.ifa_name,
                  let dataPointer = interface.pointee.ifa_data
            else { continue }

            let name = String(cString: namePointer)
            guard seenNames.insert(name).inserted else { continue }
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
        let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
            var rawUsage: rusage_info_t? = UnsafeMutableRawPointer(usagePointer)
            return proc_pid_rusage(pid, RUSAGE_INFO_V2, &rawUsage)
        }
        guard result == 0 else { return nil }

        var nameBuffer = Array(repeating: CChar(0), count: Int(MAXCOMLEN) + 1)
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard nameLength > 0 else { return nil }

        return ProcessCounters(
            cpuNanoseconds: usage.ri_user_time + usage.ri_system_time,
            residentBytes: usage.ri_resident_size,
            name: String(cString: nameBuffer)
        )
    }
}
