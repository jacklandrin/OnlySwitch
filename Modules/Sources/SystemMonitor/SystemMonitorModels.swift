import Foundation

public enum MetricAvailability<Value: Equatable & Sendable>: Equatable, Sendable {
    case available(Value)
    case unavailable

    public var value: Value? {
        guard case let .available(value) = self else { return nil }
        return value
    }
}

extension MetricAvailability: Codable where Value: Codable {}

public enum SystemMonitorMetric: String, CaseIterable, Codable, Hashable, Sendable {
    case cpu
    case gpu
    case memory
    case disk
    case network

    public var supportsDisclosure: Bool {
        switch self {
        case .cpu, .memory, .network:
            true
        case .gpu, .disk:
            false
        }
    }
}

public struct SystemMonitorProcess: Codable, Equatable, Identifiable, Sendable {
    public let pid: Int32
    public let name: String
    public let cpuUsage: MetricAvailability<Double>
    public let memoryBytes: MetricAvailability<UInt64>
    public let downloadBytesPerSecond: MetricAvailability<Double>
    public let uploadBytesPerSecond: MetricAvailability<Double>

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        name: String,
        cpuUsage: MetricAvailability<Double> = .unavailable,
        memoryBytes: MetricAvailability<UInt64> = .unavailable,
        downloadBytesPerSecond: MetricAvailability<Double> = .unavailable,
        uploadBytesPerSecond: MetricAvailability<Double> = .unavailable
    ) {
        self.pid = pid
        self.name = name
        self.cpuUsage = cpuUsage
        self.memoryBytes = memoryBytes
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

public struct SystemMonitorMemory: Codable, Equatable, Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let compressedBytes: UInt64
    public let cachedBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressure: MetricAvailability<SystemMonitorMemoryPressure>

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        compressedBytes: UInt64 = 0,
        cachedBytes: UInt64 = 0,
        swapUsedBytes: UInt64 = 0,
        pressure: MetricAvailability<SystemMonitorMemoryPressure> = .unavailable
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }

    public var usage: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

public enum SystemMonitorMemoryPressure: String, Codable, Equatable, Sendable {
    case normal
    case warning
    case critical
}

/// Static hardware facts captured when a monitor sampler is created.
///
/// The operating system does not expose every fact on every Mac. GPU core
/// count is supplied by an optional, undocumented app-side collector, so
/// consumers must retain the distinction between an unavailable value and a
/// zero value.
public struct SystemMonitorHardware: Codable, Equatable, Sendable {
    public let cpu: SystemMonitorProcessor
    public let gpu: SystemMonitorProcessor

    public init(
        cpu: SystemMonitorProcessor = .unavailable,
        gpu: SystemMonitorProcessor = .unavailable
    ) {
        self.cpu = cpu
        self.gpu = gpu
    }
}

public struct SystemMonitorProcessor: Codable, Equatable, Sendable {
    public let model: MetricAvailability<String>
    public let physicalCoreCount: MetricAvailability<Int>
    public let logicalCoreCount: MetricAvailability<Int>

    public init(
        model: MetricAvailability<String> = .unavailable,
        physicalCoreCount: MetricAvailability<Int> = .unavailable,
        logicalCoreCount: MetricAvailability<Int> = .unavailable
    ) {
        self.model = model
        self.physicalCoreCount = physicalCoreCount
        self.logicalCoreCount = logicalCoreCount
    }

    public static let unavailable = Self()
}

public struct SystemMonitorDisk: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let temperatureCelsius: MetricAvailability<Double>

    public init(
        id: String,
        name: String,
        totalBytes: UInt64,
        usedBytes: UInt64,
        temperatureCelsius: MetricAvailability<Double> = .unavailable
    ) {
        self.id = id
        self.name = name
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.temperatureCelsius = temperatureCelsius
    }

    public var usage: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

public struct SystemMonitorNetwork: Codable, Equatable, Sendable {
    public let totalDownloadedBytes: UInt64
    public let totalUploadedBytes: UInt64
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public let details: SystemMonitorNetworkDetails?

    public init(
        totalDownloadedBytes: UInt64,
        totalUploadedBytes: UInt64,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double,
        details: SystemMonitorNetworkDetails? = nil
    ) {
        self.totalDownloadedBytes = totalDownloadedBytes
        self.totalUploadedBytes = totalUploadedBytes
        self.downloadBytesPerSecond = max(downloadBytesPerSecond, 0)
        self.uploadBytesPerSecond = max(uploadBytesPerSecond, 0)
        self.details = details
    }
}

public struct SystemMonitorNetworkDetails: Codable, Equatable, Sendable {
    public let interfaces: [SystemMonitorNetworkInterface]
    public let publicIPv4Address: String?
    public let publicIPv6Address: String?

    public init(
        interfaces: [SystemMonitorNetworkInterface] = [],
        publicIPv4Address: String? = nil,
        publicIPv6Address: String? = nil
    ) {
        self.interfaces = interfaces
        self.publicIPv4Address = publicIPv4Address
        self.publicIPv6Address = publicIPv6Address
    }
}

public struct SystemMonitorNetworkInterface: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case wifi
        case ethernet
        case other
    }

    public var id: String { name }

    public let name: String
    public let displayName: String
    public let kind: Kind
    public let isActive: Bool
    public let macAddress: String?
    public let localIPv4Addresses: [String]
    public let localIPv6Addresses: [String]
    public let ssid: String?
    public let signalStrength: Int?
    public let transmitRateMbps: Double?

    public init(
        name: String,
        displayName: String,
        kind: Kind,
        isActive: Bool,
        macAddress: String? = nil,
        localIPv4Addresses: [String] = [],
        localIPv6Addresses: [String] = [],
        ssid: String? = nil,
        signalStrength: Int? = nil,
        transmitRateMbps: Double? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.isActive = isActive
        self.macAddress = macAddress
        self.localIPv4Addresses = localIPv4Addresses
        self.localIPv6Addresses = localIPv6Addresses
        self.ssid = ssid
        self.signalStrength = signalStrength
        self.transmitRateMbps = transmitRateMbps
    }
}

public struct SystemMonitorSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cpuUsage: MetricAvailability<Double>
    public let cpuTemperatureCelsius: MetricAvailability<Double>
    public let gpuUsage: MetricAvailability<Double>
    public let gpuTemperatureCelsius: MetricAvailability<Double>
    public let hardware: SystemMonitorHardware
    public let memory: MetricAvailability<SystemMonitorMemory>
    public let disks: [SystemMonitorDisk]
    public let network: MetricAvailability<SystemMonitorNetwork>
    public let processes: [SystemMonitorProcess]

    public init(
        timestamp: Date,
        cpuUsage: MetricAvailability<Double> = .unavailable,
        cpuTemperatureCelsius: MetricAvailability<Double> = .unavailable,
        gpuUsage: MetricAvailability<Double> = .unavailable,
        gpuTemperatureCelsius: MetricAvailability<Double> = .unavailable,
        hardware: SystemMonitorHardware = .init(),
        memory: MetricAvailability<SystemMonitorMemory> = .unavailable,
        disks: [SystemMonitorDisk] = [],
        network: MetricAvailability<SystemMonitorNetwork> = .unavailable,
        processes: [SystemMonitorProcess] = []
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.gpuUsage = gpuUsage
        self.gpuTemperatureCelsius = gpuTemperatureCelsius
        self.hardware = hardware
        self.memory = memory
        self.disks = disks
        self.network = network
        self.processes = processes
    }
}

public struct SystemMonitorHistory: Equatable, Sendable {
    public static let maximumSampleCount = 60

    public private(set) var snapshots: [SystemMonitorSnapshot]

    public init(snapshots: [SystemMonitorSnapshot] = []) {
        self.snapshots = Array(snapshots.suffix(Self.maximumSampleCount))
    }

    public mutating func append(_ snapshot: SystemMonitorSnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > Self.maximumSampleCount {
            snapshots.removeFirst(snapshots.count - Self.maximumSampleCount)
        }
    }
}

public struct SystemMonitorPreferences: Codable, Equatable, Sendable {
    public var enabledPanelMetrics: Set<SystemMonitorMetric>
    public var menuBarMetrics: Set<SystemMonitorMetric>
    public var refreshInterval: TimeInterval

    public init(
        enabledPanelMetrics: Set<SystemMonitorMetric> = Set(SystemMonitorMetric.allCases),
        menuBarMetrics: Set<SystemMonitorMetric> = [],
        refreshInterval: TimeInterval = 1
    ) {
        self.enabledPanelMetrics = enabledPanelMetrics
        self.menuBarMetrics = menuBarMetrics
        self.refreshInterval = max(refreshInterval, 1)
    }

    public var requiresBackgroundSampling: Bool {
        menuBarMetrics.isEmpty == false
    }
}
