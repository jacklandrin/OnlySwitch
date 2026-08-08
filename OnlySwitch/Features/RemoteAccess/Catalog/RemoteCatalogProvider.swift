import Foundation
import RemoteCore
import Switches

struct RemoteCatalogProvider: Sendable {
    var catalog: @MainActor @Sendable () async throws -> [RemoteControlDescriptor]
    var status: @MainActor @Sendable (RemoteControlID, UInt64) async throws -> RemoteControlStatus
}
