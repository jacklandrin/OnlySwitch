import Foundation
import IOKit

/// Reads and writes an external display's DDC/CI speaker volume on Apple Silicon, through the
/// same private `IOAVService` I2C calls MonitorControl uses. On Intel Macs, or if the symbols
/// are missing, every call reports the display as unsupported.
///
/// I2C round-trips block for tens of milliseconds, so all access runs on a private serial queue.
public final class DDCDisplayController: @unchecked Sendable {
    public static let shared = DDCDisplayController()

    private typealias CreateService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias TransferI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private struct Display {
        let name: String?
        let service: CFTypeRef
        let registryEntryID: UInt64
        let identity: DDCDisplayIdentity?
    }

    private struct Symbols {
        let create: CreateService
        let write: TransferI2C
        let read: TransferI2C
    }

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    private let queue = DispatchQueue(label: "com.onlyswitch.display-ddc")
    private let symbols: Symbols?
    private let brightnessWriteGate = DDCBrightnessWriteGate()
    /// Display maximums, needed to scale writes. Only touched on ``queue``.
    private var maximums: [String: Int] = [:]
    private var brightnessGeneration: UInt64 = 0
    private var brightnessServices: [UInt64: (display: Display, maximum: Int)] = [:]

    /// Rebuilds verified luminance inventory on the same queue used by speaker volume.
    public func brightnessDisplays() async -> [DDCBrightnessReading] {
        brightnessWriteGate.invalidate()
        return await perform { [self] in
            brightnessGeneration &+= 1
            brightnessServices.removeAll()
            maximums.removeAll()
            return externalDisplays().compactMap { display in
                guard let identity = display.identity, identity.serial != 0,
                      let reading = read(DDCPacket.luminance, from: display.service),
                      reading.maximum <= 255 else { return nil }
                brightnessServices[display.registryEntryID] = (display, reading.maximum)
                return DDCBrightnessReading(token: .init(registryEntryID: display.registryEntryID,
                                                         generation: brightnessGeneration),
                                            identity: identity, percent: reading.percent)
            }
        }
    }

    @discardableResult
    public func setBrightness(_ percent: Int, token: DDCDisplayToken) async -> Bool {
        let request = brightnessWriteGate.begin(display: token.registryEntryID)
        return await withTaskCancellationHandler {
            defer { brightnessWriteGate.cancel(display: token.registryEntryID, request: request) }
            if Task.isCancelled { brightnessWriteGate.cancel(display: token.registryEntryID, request: request) }
            return await perform { [self] in
                guard brightnessWriteGate.isCurrent(display: token.registryEntryID, request: request),
                      token.generation == brightnessGeneration,
                      let cached = brightnessServices[token.registryEntryID] else { return false }
                let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(token.registryEntryID))
                guard entry != 0 else { return false }
                defer { IOObjectRelease(entry) }
                // Check immediately before the first I2C transaction, not only at submission.
                guard brightnessWriteGate.isCurrent(display: token.registryEntryID, request: request) else { return false }
                return write(DDCPacket.writeRequest(vcp: DDCPacket.luminance,
                                                   value: DDCReading.value(forPercent: percent, maximum: cached.maximum)),
                             to: cached.display.service)
            }
        } onCancel: { [brightnessWriteGate] in
            brightnessWriteGate.cancel(display: token.registryEntryID, request: request)
        }
    }

    public func invalidateBrightnessDisplays() async {
        brightnessWriteGate.invalidate()
        await perform { [self] in
            brightnessGeneration &+= 1
            brightnessServices.removeAll()
            maximums.removeAll()
        }
    }

    private init() {
        let handle = dlopen(nil, RTLD_NOW)
        if let create = dlsym(handle, "IOAVServiceCreateWithService"),
           let write = dlsym(handle, "IOAVServiceWriteI2C"),
           let read = dlsym(handle, "IOAVServiceReadI2C") {
            symbols = Symbols(create: unsafeBitCast(create, to: CreateService.self),
                              write: unsafeBitCast(write, to: TransferI2C.self),
                              read: unsafeBitCast(read, to: TransferI2C.self))
        } else {
            symbols = nil
        }
    }

    /// The speaker volume (`0...100`) of the display that plays `audioDeviceName`, or `nil`
    /// when that display cannot be identified or does not answer DDC.
    public func speakerVolume(forAudioDeviceNamed audioDeviceName: String) async -> Int? {
        await perform { [self] in
            guard let display = display(forAudioDeviceNamed: audioDeviceName),
                  let reading = read(DDCPacket.speakerVolume, from: display.service) else { return nil }
            maximums[audioDeviceName] = reading.maximum
            return reading.percent
        }
    }

    /// Returns whether the write was sent. DDC writes are not acknowledged by the display.
    @discardableResult
    public func setSpeakerVolume(_ percent: Int, forAudioDeviceNamed audioDeviceName: String) async -> Bool {
        await perform { [self] in
            guard let display = display(forAudioDeviceNamed: audioDeviceName) else { return false }
            let maximum: Int
            if let cached = maximums[audioDeviceName] {
                maximum = cached
            } else {
                guard let reading = read(DDCPacket.speakerVolume, from: display.service) else { return false }
                maximum = reading.maximum
                maximums[audioDeviceName] = maximum
            }
            let value = DDCReading.value(forPercent: percent, maximum: maximum)
            return write(DDCPacket.writeRequest(vcp: DDCPacket.speakerVolume, value: value), to: display.service)
        }
    }

    private func perform<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: - I2C (on `queue`)

    private func read(_ vcp: UInt8, from service: CFTypeRef) -> DDCReading? {
        guard let symbols else { return nil }
        var reply = [UInt8](repeating: 0, count: DDCPacket.readReplyCount)
        for _ in 0..<4 {
            guard write(DDCPacket.readRequest(vcp: vcp), to: service) else {
                usleep(20_000)
                continue
            }
            usleep(50_000)
            let status = reply.withUnsafeMutableBytes {
                symbols.read(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            if status == kIOReturnSuccess, let reading = DDCPacket.parseReadReply(reply, vcp: vcp) {
                return reading
            }
            usleep(20_000)
        }
        return nil
    }

    /// Sent twice, as MonitorControl does: displays drop single requests surprisingly often.
    private func write(_ packet: [UInt8], to service: CFTypeRef) -> Bool {
        guard let symbols else { return false }
        var packet = packet
        var sent = false
        for _ in 0..<2 {
            usleep(10_000)
            let status = packet.withUnsafeMutableBytes {
                symbols.write(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            if status == kIOReturnSuccess { sent = true }
        }
        return sent
    }

    // MARK: - Display discovery (on `queue`)

    private func display(forAudioDeviceNamed audioDeviceName: String) -> Display? {
        let displays = externalDisplays()
        guard let index = DDCDisplayMatcher.index(forAudioDeviceNamed: audioDeviceName,
                                                  displayNames: displays.map(\.name)) else { return nil }
        return displays[index]
    }

    /// Each external `DCPAVServiceProxy` follows its framebuffer in the service plane, and that
    /// framebuffer carries the EDID product name in `DisplayAttributes`.
    private func externalDisplays() -> [Display] {
        guard let symbols else { return [] }
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        let framebuffers = framebufferIdentities()
        var displays: [Display] = []
        var productName: String?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let attributes = property("DisplayAttributes", of: entry) as? [String: Any],
               let product = attributes["ProductAttributes"] as? [String: Any] {
                productName = product["ProductName"] as? String
            }
            guard IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0 else { continue }
            defer { productName = nil }
            guard property("Location", of: entry) as? String == "External",
                  let service = symbols.create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &registryID) == KERN_SUCCESS else { continue }
            displays.append(Display(name: productName, service: service, registryEntryID: registryID, identity: displayIdentity(of: entry) ?? framebufferIdentity(of: entry, framebuffers: framebuffers)))
        }
        return displays
    }

    private func framebufferIdentities() -> [DDCFramebufferIdentity] {
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [DDCFramebufferIdentity] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let attributes = property("DisplayAttributes", of: entry) as? [String: Any],
                  let product = attributes["ProductAttributes"] as? [String: Any],
                  let vendor = (product["LegacyManufacturerID"] ?? product["ManufacturerID"]) as? NSNumber,
                  let model = product["ProductID"] as? NSNumber,
                  let serial = product["SerialNumber"] as? NSNumber else { continue }
            var connectorEntry: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &connectorEntry) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(connectorEntry) }
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(connectorEntry, &name) == KERN_SUCCESS else { continue }
            let connector = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            var familyEntry: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(connectorEntry, kIOServicePlane, &familyEntry) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(familyEntry) }
            var family: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(familyEntry, &family) == KERN_SUCCESS else { continue }
            result.append(.init(connector: connector, family: family,
                                identity: .init(vendor: vendor.uint32Value, product: model.uint32Value, serial: serial.uint32Value)))
        }
        return result
    }

    private func framebufferIdentity(of entry: io_registry_entry_t, framebuffers: [DDCFramebufferIdentity]) -> DDCDisplayIdentity? {
        var names: [String] = []
        var ancestors: [UInt64] = []
        var current = entry
        IOObjectRetain(current)
        for _ in 0..<32 {
            var name = [CChar](repeating: 0, count: 128)
            if IORegistryEntryGetName(current, &name) == KERN_SUCCESS {
                names.append(String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
            var identity: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(current, &identity) == KERN_SUCCESS { ancestors.append(identity) }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS, parent != 0 else { return DDCFramebufferIdentity.match(endpointNames: names, ancestors: ancestors, framebuffers: framebuffers) }
            current = parent
        }
        IOObjectRelease(current)
        return DDCFramebufferIdentity.match(endpointNames: names, ancestors: ancestors, framebuffers: framebuffers)
    }

    /// Only inspect this service and its ancestors, never a neighboring framebuffer's identity.
    private func displayIdentity(of entry: io_registry_entry_t) -> DDCDisplayIdentity? {
        for key in ["IODisplayEDID", "EDID"] {
            if let value = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString,
                kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Data,
               let identity = DDCDisplayIdentity(edid: Array(value)) { return identity }
        }
        if let attributes = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "DisplayAttributes" as CFString,
            kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? [String: Any],
           let product = attributes["ProductAttributes"] as? [String: Any],
           let vendor = (product["LegacyManufacturerID"] ?? product["ManufacturerID"]) as? NSNumber,
           let model = product["ProductID"] as? NSNumber,
           let serial = product["SerialNumber"] as? NSNumber {
            return .init(vendor: vendor.uint32Value, product: model.uint32Value, serial: serial.uint32Value)
        }
        return nil
    }

    private func property(_ key: String, of entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
