import Foundation
import RemoteCore

struct MacDashboardLayout: Codable, Equatable, Sendable {
    let macID: UUID
    var selectedControlIDs: Set<RemoteControlID>
    var order: [RemoteControlID]
}

struct RemoteCatalogCache: Codable, Equatable, Sendable {
    var revision: UInt64
    var controls: [RemoteControlDescriptor]
}
