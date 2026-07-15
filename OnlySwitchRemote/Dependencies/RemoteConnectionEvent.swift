import Foundation
import Network
import RemoteCore

struct DiscoveredMac: Equatable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let endpoint: NWEndpoint
    let protocolVersion: RemoteProtocolVersion
}

enum RemoteConnectionEvent: Equatable, Sendable {
    case connecting(UUID)
    case authenticated(UUID)
    case offline(UUID, String?)
    case revoked(UUID)
    case catalog(UUID, UInt64, [RemoteControlDescriptor])
    case status(UUID, RemoteControlStatus)
    case action(UUID, RemoteActionResult)
}

enum DiscoveryEvent: Equatable, Sendable {
    case added(DiscoveredMac)
    case removed(UUID)
}
