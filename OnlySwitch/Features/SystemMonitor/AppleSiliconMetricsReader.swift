import Darwin
import Foundation
import IOKit

/// Decodes the SMC temperature payload formats used by Apple Silicon Macs.
///
/// Keeping byte decoding and key classification separate from the private IOKit transport makes
/// the most failure-prone part of the integration deterministic and testable.
enum SMCTemperatureCodec {
    private static let sp78 = fourCharacterCode("sp78")
    private static let floatingPoint = fourCharacterCode("flt ")
    private static let m3CPUKeys: Set<String> = [
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"
    ]
    private static let m3GPUKeys: Set<String> = [
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"
    ]

    static func decode(dataType: UInt32, bytes: [UInt8]) -> Double? {
        switch dataType {
        case sp78:
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256
        case floatingPoint:
            guard bytes.count >= 4 else { return nil }
            let bitPattern = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            let value = Double(Float(bitPattern: bitPattern))
            return value.isFinite ? value : nil
        default:
            return nil
        }
    }

    static func isPlausible(_ celsius: Double) -> Bool {
        celsius.isFinite && (10 ..< 125).contains(celsius)
    }

    static func isCPUKey(_ key: String, chipModel: String?) -> Bool {
        if key.hasPrefix("Tp") || key.hasPrefix("Te") { return true }
        return isM3(chipModel) && m3CPUKeys.contains(key)
    }

    static func isGPUKey(_ key: String, chipModel: String?) -> Bool {
        key.hasPrefix("Tg") || (isM3(chipModel) && m3GPUKeys.contains(key))
    }

    static func isCPUKey(_ key: UInt32, chipModel: String?) -> Bool {
        isCPUKey(string(for: key), chipModel: chipModel)
    }

    static func isGPUKey(_ key: UInt32, chipModel: String?) -> Bool {
        isGPUKey(string(for: key), chipModel: chipModel)
    }

    private static func fourCharacterCode(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func isM3(_ chipModel: String?) -> Bool {
        chipModel?.range(of: #"\bM3(?:\s|$)"#, options: .regularExpression) != nil
    }

    private static func string(for value: UInt32) -> String {
        String(decoding: [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ], as: UTF8.self)
    }
}

/// Reads Apple Silicon GPU counters and CPU/GPU sensors exposed through undocumented IOKit services.
///
/// `AGXAccelerator`'s `PerformanceStatistics`, `gpu-core-count`, and the AppleSMC user client
/// are implementation details rather than supported macOS APIs. They are intentionally confined
/// to this type, only used on Apple Silicon, and treated as optional so an OS or hardware change
/// cannot affect monitor availability or process stability. This path is unsuitable for Mac App
/// Store distribution without separately validating Apple's current review policy.
struct PrivateAppleSiliconMetricsReader {
    struct Reading {
        let usage: Double?
        let cpuTemperatureCelsius: Double?
        let gpuTemperatureCelsius: Double?
    }

    private struct TemperatureSensor {
        let key: UInt32
        let name: String
        let dataType: UInt32
        let dataSize: UInt32
    }

    private struct TemperatureSensors {
        let cpu: [TemperatureSensor]
        let gpu: [TemperatureSensor]
    }

    private static let maximumSensorKeys = 4_096
    private var smcConnection: io_connect_t = IO_OBJECT_NULL
    private var temperatureSensors: TemperatureSensors?

    mutating func sample(chipModel: String?) -> Reading {
        guard Self.isAppleSilicon else {
            return Reading(
                usage: nil,
                cpuTemperatureCelsius: nil,
                gpuTemperatureCelsius: nil
            )
        }
        let temperatures = readTemperatures(chipModel: chipModel)
        return Reading(
            usage: Self.readUsage(),
            cpuTemperatureCelsius: temperatures.cpu,
            gpuTemperatureCelsius: temperatures.gpu
        )
    }

    static func usage() -> Double? {
        guard isAppleSilicon else { return nil }
        return readUsage()
    }

    mutating func close() {
        guard smcConnection != IO_OBJECT_NULL else { return }
        IOServiceClose(smcConnection)
        smcConnection = IO_OBJECT_NULL
        temperatureSensors = nil
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

    private mutating func readTemperatures(
        chipModel: String?
    ) -> (cpu: Double?, gpu: Double?) {
        guard openSMCIfNeeded() else { return (nil, nil) }
        if temperatureSensors == nil {
            let discovered = discoverTemperatureSensors(chipModel: chipModel)
            // An empty response can be transient while the private service is waking up.
            if discovered.cpu.isEmpty == false, discovered.gpu.isEmpty == false {
                temperatureSensors = discovered
            }
        }
        let sensors = temperatureSensors ?? discoverTemperatureSensors(chipModel: chipModel)
        return (
            hottestTemperature(from: sensors.cpu),
            hottestTemperature(from: sensors.gpu)
        )
    }

    private mutating func openSMCIfNeeded() -> Bool {
        if smcConnection != IO_OBJECT_NULL { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &smcConnection) == KERN_SUCCESS
    }

    private func discoverTemperatureSensors(chipModel: String?) -> TemperatureSensors {
        guard let keyCount = readUnsignedInteger(key: Self.fourCharacterCode("#KEY")),
              keyCount > 0, keyCount <= Self.maximumSensorKeys
        else { return TemperatureSensors(cpu: [], gpu: []) }

        var cpu: [TemperatureSensor] = []
        var gpu: [TemperatureSensor] = []
        for index in 0 ..< keyCount {
            guard let key = key(at: index) else { continue }
            let name = Self.string(for: key)
            let isCPU = SMCTemperatureCodec.isCPUKey(name, chipModel: chipModel)
            let isGPU = SMCTemperatureCodec.isGPUKey(name, chipModel: chipModel)
            guard isCPU || isGPU, let keyInfo = readKeyInfo(key: key) else { continue }

            let sensor = TemperatureSensor(
                key: key,
                name: name,
                dataType: keyInfo.dataType,
                dataSize: keyInfo.dataSize
            )
            guard let celsius = readTemperature(sensor: sensor),
                  SMCTemperatureCodec.isPlausible(celsius)
            else { continue }
            if isCPU { cpu.append(sensor) }
            if isGPU { gpu.append(sensor) }
        }

        // M4 exposes several other Tp/Te values that are not CPU core sensors. Prefer the
        // observed core-die set used by hardware monitors, while retaining classified fallback
        // keys for future variants whose suffixes differ.
        if chipModel?.contains("M4") == true {
            let m4CoreKeys: Set<String> = [
                "Te05", "Te0S", "Te09", "Te0H",
                "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"
            ]
            let preferredCPU = cpu.filter { m4CoreKeys.contains($0.name) }
            if preferredCPU.isEmpty == false { cpu = preferredCPU }
        }
        return TemperatureSensors(cpu: cpu, gpu: gpu)
    }

    private func key(at index: Int) -> UInt32? {
        var input = SMCParameter()
        input.data8 = SMCCommand.keyFromIndex.rawValue
        input.data32 = UInt32(index)
        guard let output = callSMC(&input), output.result == 0, output.key != 0 else { return nil }
        return output.key
    }

    private func readUnsignedInteger(key: UInt32) -> Int? {
        guard let value = readValue(key: key), value.bytes.isEmpty == false else { return nil }
        let unsignedValue = value.bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Int(unsignedValue)
    }

    private func hottestTemperature(from sensors: [TemperatureSensor]) -> Double? {
        sensors
            .compactMap { readTemperature(sensor: $0) }
            .filter(SMCTemperatureCodec.isPlausible)
            .max()
    }

    private func readTemperature(sensor: TemperatureSensor) -> Double? {
        guard let bytes = readBytes(key: sensor.key, dataSize: sensor.dataSize) else { return nil }
        return SMCTemperatureCodec.decode(dataType: sensor.dataType, bytes: bytes)
    }

    private func readKeyInfo(key: UInt32) -> SMCKeyInfo? {
        var infoRequest = SMCParameter()
        infoRequest.key = key
        infoRequest.data8 = SMCCommand.keyInfo.rawValue
        guard let info = callSMC(&infoRequest), info.result == 0,
              info.keyInfo.dataSize > 0, info.keyInfo.dataSize <= 32
        else { return nil }
        return info.keyInfo
    }

    private func readValue(key: UInt32) -> (dataType: UInt32, bytes: [UInt8])? {
        guard let keyInfo = readKeyInfo(key: key),
              let bytes = readBytes(key: key, dataSize: keyInfo.dataSize)
        else { return nil }
        return (keyInfo.dataType, bytes)
    }

    private func readBytes(key: UInt32, dataSize: UInt32) -> [UInt8]? {
        var readRequest = SMCParameter()
        readRequest.key = key
        readRequest.keyInfo.dataSize = dataSize
        readRequest.data8 = SMCCommand.readKey.rawValue
        guard let value = callSMC(&readRequest), value.result == 0 else { return nil }

        return Array(value.bytes.prefix(Int(dataSize)))
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
        // C gives this nested structure a 12-byte size. Swift otherwise packs the next outer
        // property immediately after byte 9, so model the ABI's trailing alignment explicitly.
        var reserved0: UInt8 = 0
        var reserved1: UInt8 = 0
        var reserved2: UInt8 = 0
    }

    /// This mirrors the private 80-byte C ABI. Alignment belongs to the nested key-info record;
    /// adding a standalone field between it and `result` would shift the response fields.
    private struct SMCParameter {
        var key: UInt32 = 0
        var version = SMCVersion()
        var powerLimit = SMCPowerLimit()
        var keyInfo = SMCKeyInfo()
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
