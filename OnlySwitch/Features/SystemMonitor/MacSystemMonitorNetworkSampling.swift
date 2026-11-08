import Darwin
import CoreWLAN
import Foundation
import SystemConfiguration
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

struct NetworkAddressGroups: Equatable, Sendable {
    let ipv4: [String]
    let ipv6: [String]
}

enum NetworkAddressParser {
    static func isValidIPLiteral(_ address: String) -> Bool {
        family(of: address) != nil
    }

    static func group(addresses: [String]) -> NetworkAddressGroups {
        var ipv4: [String] = []
        var ipv6: [String] = []
        var seenIPv4 = Set<String>()
        var seenIPv6 = Set<String>()

        for address in addresses {
            switch family(of: address) {
            case AF_INET where isLoopback(address) == false:
                if seenIPv4.insert(address).inserted { ipv4.append(address) }
            case AF_INET6 where isLoopback(address) == false:
                if seenIPv6.insert(address).inserted { ipv6.append(address) }
            default:
                continue
            }
        }
        return NetworkAddressGroups(ipv4: ipv4, ipv6: ipv6)
    }

    static func family(of address: String) -> Int32? {
        let literal = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address
        guard literal.isEmpty == false else { return nil }

        var ipv4 = in_addr()
        if literal.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 { return AF_INET }

        var ipv6 = in6_addr()
        if literal.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 { return AF_INET6 }
        return nil
    }

    private static func isLoopback(_ address: String) -> Bool {
        let literal = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address
        if literal == "::1" { return true }
        guard family(of: literal) == AF_INET else { return false }
        return literal.hasPrefix("127.")
    }
}

enum NetworkInterfaceClassifier {
    static func kind(
        interfaceName _: String,
        hardwareType: String?
    ) -> SystemMonitorNetworkInterface.Kind {
        let normalized = hardwareType?.lowercased() ?? ""
        if normalized.contains("ieee80211") || normalized.contains("wi-fi") || normalized.contains("airport") {
            return .wifi
        }
        if normalized.contains("ethernet") { return .ethernet }
        return .other
    }
}

struct PublicIPAddresses: Equatable, Sendable {
    let ipv4: String?
    let ipv6: String?
}

actor PublicIPAddressProvider {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let fetch: Fetch
    private let cacheDuration: TimeInterval
    private var lastAttempt: Date?
    private var cachedIPv4: String?
    private var cachedIPv6: String?

    init(
        cacheDuration: TimeInterval = 5 * 60,
        fetch: @escaping Fetch = PublicIPAddressProvider.liveFetch
    ) {
        self.cacheDuration = cacheDuration
        self.fetch = fetch
    }

    func addresses(now: Date = Date()) async -> PublicIPAddresses {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < cacheDuration {
            return PublicIPAddresses(ipv4: cachedIPv4, ipv6: cachedIPv6)
        }
        lastAttempt = now

        async let ipv4 = fetchLiteral(
            from: URL(string: "https://api.ipify.org")!,
            expectedFamily: AF_INET
        )
        async let ipv6 = fetchLiteral(
            from: URL(string: "https://api6.ipify.org")!,
            expectedFamily: AF_INET6
        )
        let (newIPv4, newIPv6) = await (ipv4, ipv6)
        if let newIPv4 { cachedIPv4 = newIPv4 }
        if let newIPv6 { cachedIPv6 = newIPv6 }
        return PublicIPAddresses(ipv4: cachedIPv4, ipv6: cachedIPv6)
    }

    private func fetchLiteral(from url: URL, expectedFamily: Int32) async -> String? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await fetch(request)
            guard Task.isCancelled == false,
                  let response = response as? HTTPURLResponse,
                  (200 ..< 300).contains(response.statusCode),
                  let literal = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  NetworkAddressParser.family(of: literal) == expectedFamily
            else { return nil }
            return literal
        } catch {
            return nil
        }
    }

    nonisolated private static func liveFetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

private struct NetworkInterfaceMetadata {
    let displayName: String
    let hardwareType: String?
}

private struct NetworkInterfaceAccumulator {
    var flags: UInt32 = 0
    var addresses: [String] = []
    var macAddress: String?
}

enum NetworkDetailsSampler {
    static func read(publicAddresses: PublicIPAddresses) -> SystemMonitorNetworkDetails {
        let metadata = interfaceMetadata()
        let primaryInterfaces = primaryInterfaceNames()
        let accumulated = accumulatedInterfaces()
        let wifiClient = CWWiFiClient.shared()

        let interfaces = accumulated.compactMap { name, raw -> SystemMonitorNetworkInterface? in
            let isActive = (raw.flags & UInt32(IFF_UP)) != 0
                && (raw.flags & UInt32(IFF_LOOPBACK)) == 0
            guard isActive else { return nil }

            let interfaceMetadata = metadata[name]
            let kind = NetworkInterfaceClassifier.kind(
                interfaceName: name,
                hardwareType: interfaceMetadata?.hardwareType
            )
            let addresses = NetworkAddressParser.group(addresses: raw.addresses)
            guard addresses.ipv4.isEmpty == false
                    || addresses.ipv6.isEmpty == false
                    || primaryInterfaces.contains(name)
            else { return nil }

            // VPN/tunnel and virtual bridge devices can be numerous. Keep them only when they
            // own the primary route; Wi-Fi and Ethernet remain visible whenever active.
            guard kind != .other || primaryInterfaces.contains(name) else { return nil }

            let wifiInterface = kind == .wifi ? wifiClient.interface(withName: name) : nil
            return SystemMonitorNetworkInterface(
                name: name,
                displayName: interfaceMetadata?.displayName ?? name,
                kind: kind,
                isActive: true,
                macAddress: raw.macAddress,
                localIPv4Addresses: addresses.ipv4,
                localIPv6Addresses: addresses.ipv6,
                ssid: wifiInterface?.ssid(),
                signalStrength: wifiInterface.map { $0.rssiValue() },
                transmitRateMbps: wifiInterface.map { $0.transmitRate() }
            )
        }
        .sorted { lhs, rhs in
            let lhsPrimary = primaryInterfaces.contains(lhs.name)
            let rhsPrimary = primaryInterfaces.contains(rhs.name)
            if lhsPrimary != rhsPrimary { return lhsPrimary }
            if lhs.kind != rhs.kind { return lhs.kind == .wifi }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return SystemMonitorNetworkDetails(
            interfaces: interfaces,
            publicIPv4Address: publicAddresses.ipv4,
            publicIPv6Address: publicAddresses.ipv6
        )
    }

    private static func interfaceMetadata() -> [String: NetworkInterfaceMetadata] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        return interfaces.reduce(into: [:]) { result, interface in
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return }
            result[name] = NetworkInterfaceMetadata(
                displayName: (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? name,
                hardwareType: SCNetworkInterfaceGetInterfaceType(interface) as String?
            )
        }
    }

    private static func primaryInterfaceNames() -> Set<String> {
        ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"].reduce(into: Set<String>()) { result, key in
            guard let value = SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any],
                  let name = value[kSCDynamicStorePropNetPrimaryInterface as String] as? String
            else { return }
            result.insert(name)
        }
    }

    private static func accumulatedInterfaces() -> [String: NetworkInterfaceAccumulator] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [:] }
        defer { freeifaddrs(first) }

        var result: [String: NetworkInterfaceAccumulator] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            guard let namePointer = interface.pointee.ifa_name,
                  let address = interface.pointee.ifa_addr
            else { continue }

            let name = String(cString: namePointer)
            var item = result[name] ?? NetworkInterfaceAccumulator()
            item.flags |= interface.pointee.ifa_flags
            switch Int32(address.pointee.sa_family) {
            case AF_INET, AF_INET6:
                if let literal = numericAddress(address) { item.addresses.append(literal) }
            case AF_LINK:
                item.macAddress = macAddress(address)
            default:
                break
            }
            result[name] = item
        }
        return result
    }

    private static func numericAddress(_ address: UnsafePointer<sockaddr>) -> String? {
        let minimumLength: Int
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            minimumLength = MemoryLayout<sockaddr_in>.size
        case AF_INET6:
            minimumLength = MemoryLayout<sockaddr_in6>.size
        default:
            return nil
        }
        guard Int(address.pointee.sa_len) >= minimumLength else { return nil }

        var host = Array(repeating: CChar(0), count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        let literal = String(cString: host)
        return literal.isEmpty ? nil : literal
    }

    private static func macAddress(_ address: UnsafePointer<sockaddr>) -> String? {
        let linkAddress = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_dl.self)
        let length = Int(linkAddress.pointee.sdl_alen)
        let nameLength = Int(linkAddress.pointee.sdl_nlen)
        guard length > 0,
              let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \sockaddr_dl.sdl_data),
              Int(address.pointee.sa_len) >= dataOffset,
              nameLength <= Int(address.pointee.sa_len) - dataOffset,
              length <= Int(address.pointee.sa_len) - dataOffset - nameLength
        else { return nil }

        let bytes = UnsafeRawPointer(linkAddress)
            .advanced(by: dataOffset + nameLength)
            .assumingMemoryBound(to: UInt8.self)
        return (0 ..< length)
            .map { String(format: "%02X", bytes[$0]) }
            .joined(separator: ":")
    }
}
