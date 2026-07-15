public struct RemoteProtocolVersion: Codable, Equatable, Sendable {
    public static let current = Self(major: 1, minor: 1)

    public let major: UInt16
    public let minor: UInt16

    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }

    public func isCompatible(with other: Self) -> Bool {
        negotiated(with: other) != nil
    }

    public func negotiated(with other: Self) -> Self? {
        guard major == other.major,
              minor <= Self.current.minor,
              other.minor <= Self.current.minor else { return nil }
        return Self(major: major, minor: min(minor, other.minor))
    }

    public var supportsAuthenticatedRevocation: Bool { minor >= 1 }
}
