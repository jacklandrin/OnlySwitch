import Foundation

/// Least-recently-used set of pages whose web views stay alive. The most recent ID is last.
public struct BrowserPageCache: Equatable, Sendable {
    public let capacity: Int
    public private(set) var order: [UUID] = []

    public init(capacity: Int = 3) {
        self.capacity = max(1, capacity)
    }

    /// Marks `id` as most recently used and returns the IDs that no longer fit, oldest first.
    @discardableResult
    public mutating func touch(_ id: UUID) -> [UUID] {
        order.removeAll { $0 == id }
        order.append(id)
        let overflow = max(0, order.count - capacity)
        let evicted = Array(order.prefix(overflow))
        order.removeFirst(overflow)
        return evicted
    }

    public mutating func remove(_ id: UUID) {
        order.removeAll { $0 == id }
    }
}
