import Foundation
import RemoteCore

struct MacDashboardLayout: Codable, Equatable, Sendable {
    let macID: UUID
    var selectedControlIDs: Set<RemoteControlID>
    var order: [RemoteControlID]
}
