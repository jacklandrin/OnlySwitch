import Foundation

/// Latest-intent/cancellation state can change while the serial I2C queue is busy.
/// Every field is protected by the lock; no service reference crosses this boundary.
final class DDCBrightnessWriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [UInt64: UUID] = [:]
    func begin(display: UInt64) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let request = UUID(); requests[display] = request; return request
    }
    func isCurrent(display: UInt64, request: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return requests[display] == request
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        requests.removeAll()
    }
    func cancel(display: UInt64, request: UUID) {
        lock.lock(); defer { lock.unlock() }
        if requests[display] == request { requests.removeValue(forKey: display) }
    }
}
