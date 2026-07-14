public struct RemoteProtocolVersion: Codable, Equatable, Sendable {
    public static let current = Self(major: 1, minor: 0)

    public let major: UInt16
    public let minor: UInt16

    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }

    public func isCompatible(with other: Self) -> Bool {
        major == other.major
    }
}
