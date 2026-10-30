/// EDID identity. A nonzero, unique serial is required before associating an I2C service with a screen.
public struct DDCDisplayIdentity: Equatable, Sendable {
    public let vendor: UInt32
    public let product: UInt32
    public let serial: UInt32
    public init(vendor: UInt32, product: UInt32, serial: UInt32) {
        self.vendor = vendor; self.product = product; self.serial = serial
    }
    public init?(edid: [UInt8]) {
        guard edid.count >= 128, Array(edid.prefix(8)) == [0,255,255,255,255,255,255,0],
              edid.prefix(128).reduce(UInt8(0), &+) == 0 else { return nil }
        self.init(vendor: UInt32(edid[8]) << 8 | UInt32(edid[9]),
                  product: UInt32(edid[10]) | UInt32(edid[11]) << 8,
                  serial: UInt32(edid[12]) | UInt32(edid[13]) << 8 | UInt32(edid[14]) << 16 | UInt32(edid[15]) << 24)
    }
    public func uniqueIndex(in candidates: [Self]) -> Int? {
        guard serial != 0, vendor != 0, product != 0 else { return nil }
        let matches = candidates.indices.filter { candidates[$0] == self }
        return matches.count == 1 ? matches[0] : nil
    }
}

public struct DDCDisplayToken: Hashable, Sendable {
    public let registryEntryID: UInt64
    public let generation: UInt64
    public init(registryEntryID: UInt64, generation: UInt64) {
        self.registryEntryID = registryEntryID; self.generation = generation
    }
}
public struct DDCBrightnessReading: Equatable, Sendable {
    public let token: DDCDisplayToken
    public let identity: DDCDisplayIdentity
    public let percent: Int
    public init(token: DDCDisplayToken, identity: DDCDisplayIdentity, percent: Int) {
        self.token = token; self.identity = identity; self.percent = percent
    }
}

/// A DCP endpoint names its connector; framebuffer metadata must belong to that exact connector and family.
struct DDCFramebufferIdentity: Equatable, Sendable {
    let connector: String
    let family: UInt64
    let identity: DDCDisplayIdentity
    static func match(endpointNames: [String], ancestors: [UInt64], framebuffers: [Self]) -> DDCDisplayIdentity? {
        let connectors = Set(endpointNames.compactMap { name -> String? in
            let parts = name.split(separator: ":")
            guard parts.count == 3, parts[1] == "dcpav-service-epic", !parts[0].isEmpty else { return nil }
            return String(parts[0])
        })
        let matches = framebuffers.filter { connectors.contains($0.connector) && ancestors.contains($0.family) }
        return matches.count == 1 ? matches[0].identity : nil
    }
}
