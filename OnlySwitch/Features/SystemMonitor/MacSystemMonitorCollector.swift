import Darwin
import Dispatch
import Foundation
import SystemMonitor

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

enum MemoryPressureSampler {
    static func status(
        for event: DispatchSource.MemoryPressureEvent
    ) -> SystemMonitorMemoryPressure {
        if event.contains(.critical) { return .critical }
        if event.contains(.warning) { return .warning }
        return .normal
    }
}

/// Samples macOS system metrics.
///
/// This actor owns all mutable counters so rates cannot be computed from interleaved samples.
/// It uses a deliberately isolated, opt-in-by-platform private IOKit path for Apple Silicon GPU
/// metrics. If that path is absent or changes on a future macOS release, the affected values stay
/// explicitly unavailable.
actor MacSystemMonitorCollector {
    private struct SamplingProfile: Hashable {
        let metrics: Set<SystemMonitorMetric>
        let includeDetails: Bool
    }

    struct CPUTicks {
        let busy: UInt64
        let total: UInt64
    }

    struct NetworkCounters {
        let downloaded: UInt64
        let uploaded: UInt64
    }

    struct ProcessCounters {
        let cpuNanoseconds: UInt64
        let memoryBytes: UInt64?
        let name: String
        let identity: SystemMonitorProcessIdentity?
    }

    struct ProcessCPUBaseline {
        let identity: SystemMonitorProcessIdentity?
        let cpuNanoseconds: UInt64
    }

    private struct SamplingState {
        var previousCPUTicks: CPUTicks?
        var previousNetworkCounters: NetworkCounters?
        var previousProcessCPUTimes: [Int32: ProcessCPUBaseline] = [:]
        var previousNetworkUptime: TimeInterval?
        var previousProcessUptime: TimeInterval?
        var lastCollectedUptime: TimeInterval?
        var latestSnapshot: SystemMonitorSnapshot?
        var latestProcessIdentities: [Int32: SystemMonitorProcessIdentity] = [:]
    }

    private struct SampledSnapshot: Sendable {
        let snapshot: SystemMonitorSnapshot
        let processIdentities: [Int32: SystemMonitorProcessIdentity]
    }

    private var samplingStates: [SamplingProfile: SamplingState] = [:]
    private var publicAddresses = PublicIPAddresses(ipv4: nil, ipv6: nil)
    var memoryPressure: SystemMonitorMemoryPressure = .normal
    private var privateMetricsReader = PrivateAppleSiliconMetricsReader()
    private let memoryPressureSource: any DispatchSourceMemoryPressure
    private var hardware: SystemMonitorHardware?
    private let publicIPAddressProvider: PublicIPAddressProvider

    init(publicIPAddressProvider: PublicIPAddressProvider = PublicIPAddressProvider()) {
        self.publicIPAddressProvider = publicIPAddressProvider
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
        privateMetricsReader.close()
    }

    nonisolated static func liveClient(
        refreshInterval: TimeInterval = 1,
        metrics: Set<SystemMonitorMetric> = Set(SystemMonitorMetric.allCases),
        includeDetails: Bool = true
    ) -> SystemMonitorClient {
        let collector = Self()
        return SystemMonitorClient(
            activateProcess: { target in
                SystemMonitorProcessActivation.activate(target)
            },
            snapshots: {
                collector.snapshotStream(
                    refreshInterval: refreshInterval,
                    metrics: metrics,
                    includeDetails: includeDetails
                )
            }
        )
    }

    nonisolated func snapshotStream(
        refreshInterval: TimeInterval = 1,
        metrics: Set<SystemMonitorMetric> = Set(SystemMonitorMetric.allCases),
        includeDetails: Bool = true
    ) -> AsyncThrowingStream<SystemMonitorSnapshot, Error> {
        let interval = max(refreshInterval, 1)

        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        while Task.isCancelled == false {
                            let sampled = await self.sampleForStream(
                                metrics: metrics,
                                includeDetails: includeDetails
                            )
                            let enriched = await SystemMonitorProcessActivation.enrich(
                                sampled.snapshot,
                                sampledIdentities: sampled.processIdentities
                            )
                            guard Task.isCancelled == false else { break }
                            continuation.yield(enriched)

                            do {
                                try await Task.sleep(for: .seconds(interval))
                            } catch {
                                break
                            }
                        }
                    }
                    if includeDetails && metrics.contains(.network) {
                        group.addTask {
                            while Task.isCancelled == false {
                                await self.refreshPublicAddresses()

                                do {
                                    try await Task.sleep(for: .seconds(5 * 60))
                                } catch {
                                    break
                                }
                            }
                        }
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func sample(
        metrics: Set<SystemMonitorMetric> = Set(SystemMonitorMetric.allCases),
        includeDetails: Bool = true
    ) -> SystemMonitorSnapshot {
        sampleForStream(metrics: metrics, includeDetails: includeDetails).snapshot
    }

    private func sampleForStream(
        metrics: Set<SystemMonitorMetric>,
        includeDetails: Bool
    ) -> SampledSnapshot {
        let profile = SamplingProfile(metrics: metrics, includeDetails: includeDetails)
        var state = samplingStates[profile] ?? SamplingState()
        let uptime = ProcessInfo.processInfo.systemUptime
        if let lastCollectedUptime = state.lastCollectedUptime,
           let latestSnapshot = state.latestSnapshot,
           uptime - lastCollectedUptime < 1 {
            return SampledSnapshot(
                snapshot: latestSnapshot,
                processIdentities: state.latestProcessIdentities
            )
        }

        let now = Date()
        let cpuUsage = (metrics.contains(.cpu) ? readCPUTicks() : nil).map { current in
            defer { state.previousCPUTicks = current }
            guard let previous = state.previousCPUTicks, current.total >= previous.total else { return 0.0 }
            let totalDelta = current.total - previous.total
            guard totalDelta > 0, current.busy >= previous.busy else { return 0.0 }
            return min(max(Double(current.busy - previous.busy) / Double(totalDelta), 0), 1)
        }

        let network = (metrics.contains(.network) ? readNetworkCounters() : nil).map { current in
            defer {
                state.previousNetworkCounters = current
                state.previousNetworkUptime = uptime
            }
            let seconds = state.previousNetworkUptime.map { max(uptime - $0, 0) } ?? 0
            return SystemMonitorNetwork(
                totalDownloadedBytes: current.downloaded,
                totalUploadedBytes: current.uploaded,
                downloadBytesPerSecond: NetworkRate.delta(
                    current: current.downloaded,
                    previous: state.previousNetworkCounters?.downloaded,
                    seconds: seconds
                ),
                uploadBytesPerSecond: NetworkRate.delta(
                    current: current.uploaded,
                    previous: state.previousNetworkCounters?.uploaded,
                    seconds: seconds
                ),
                details: includeDetails ? NetworkDetailsSampler.read(publicAddresses: publicAddresses) : nil
            )
        }

        let hardware = includeDetails ? hardwareDetails() : SystemMonitorHardware()
        let privateMetrics = includeDetails && (metrics.contains(.cpu) || metrics.contains(.gpu))
            ? privateMetricsReader.sample(chipModel: hardware.cpu.model.value)
            : nil
        let gpuUsage = metrics.contains(.gpu)
            ? (includeDetails ? privateMetrics?.usage : PrivateAppleSiliconMetricsReader.usage())
            : nil
        let processes: [SystemMonitorProcess]
        var sampledProcessIdentities: [Int32: SystemMonitorProcessIdentity] = [:]
        if includeDetails {
            let elapsed = state.previousProcessUptime.map { max(uptime - $0, 0) } ?? 0
            processes = readProcesses(
                elapsed: elapsed,
                previousProcessCPUTimes: &state.previousProcessCPUTimes,
                sampledProcessIdentities: &sampledProcessIdentities
            )
            state.previousProcessUptime = uptime
        } else {
            processes = []
        }
        let topProcesses = ProcessSampler.topRows(from: processes, limit: 12)
        sampledProcessIdentities = sampledProcessIdentities.filter { pid, _ in
            topProcesses.contains { $0.pid == pid }
        }
        let snapshot = SystemMonitorSnapshot(
            timestamp: now,
            cpuUsage: cpuUsage.map(MetricAvailability.available) ?? .unavailable,
            cpuTemperatureCelsius: metrics.contains(.cpu)
                ? privateMetrics?.cpuTemperatureCelsius.map(MetricAvailability.available) ?? .unavailable
                : .unavailable,
            gpuUsage: gpuUsage.map(MetricAvailability.available) ?? .unavailable,
            gpuTemperatureCelsius: metrics.contains(.gpu)
                ? privateMetrics?.gpuTemperatureCelsius.map(MetricAvailability.available) ?? .unavailable
                : .unavailable,
            hardware: hardware,
            memory: (metrics.contains(.memory) ? readMemory() : nil)
                .map(MetricAvailability.available) ?? .unavailable,
            disks: metrics.contains(.disk) ? readDisks() : [],
            network: network.map(MetricAvailability.available) ?? .unavailable,
            processes: topProcesses
        )
        state.lastCollectedUptime = uptime
        state.latestSnapshot = snapshot
        state.latestProcessIdentities = sampledProcessIdentities
        samplingStates[profile] = state
        return SampledSnapshot(snapshot: snapshot, processIdentities: sampledProcessIdentities)
    }

    private func hardwareDetails() -> SystemMonitorHardware {
        if let hardware { return hardware }
        let hardware = Self.readHardware(gpuCoreCount: PrivateAppleSiliconMetricsReader.coreCount())
        self.hardware = hardware
        return hardware
    }

    private func refreshPublicAddresses() async {
        let addresses = await publicIPAddressProvider.addresses()
        guard Task.isCancelled == false else { return }
        publicAddresses = addresses
    }
}
