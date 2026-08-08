import Foundation
import RemoteCore

actor RecentRequestCache {
    private var order: [UUID] = []
    private var results: [UUID: RemoteActionResult] = [:]
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    func result(for id: UUID) -> RemoteActionResult? {
        results[id]
    }

    func insert(_ result: RemoteActionResult, for id: UUID) {
        guard capacity > 0 else { return }
        if results[id] != nil {
            results[id] = result
            return
        }

        order.append(id)
        results[id] = result
        if order.count > capacity {
            let evictedID = order.removeFirst()
            results[evictedID] = nil
        }
    }
}
