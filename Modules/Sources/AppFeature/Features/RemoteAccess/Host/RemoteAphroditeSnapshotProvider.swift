import Aphrodite
import Foundation
import RemoteCore

private actor RemoteAphroditeRevisionClock {
    static let shared = RemoteAphroditeRevisionClock()
    private var last: UInt64 = 0

    func next() -> UInt64 {
        let wallClock = UInt64(max(1, Date.now.timeIntervalSince1970 * 1_000))
        last = max(last &+ 1, wallClock)
        return last
    }
}

enum RemoteAphroditeSnapshotProvider {
    static func liveMessages() async throws -> [RemoteMessage] {
        let library = try await AphroditePersistenceClient.liveValue.load()
        let revision = await RemoteAphroditeRevisionClock.shared.next()
        return try AphroditeRemoteSnapshotEncoder.messages(
            library: library,
            revision: revision,
            transferID: UUID()
        )
    }
}
