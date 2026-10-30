/// Tracks observed native changes separately from our own writes and invalidates overlapping sync passes.
public struct BrightnessNativeSyncState: Sendable {
    private var revision: UInt64 = 0
    private var previous: [UInt32: Double] = [:]
    public init() {}
    public mutating func beginCycle() -> UInt64 { revision &+= 1; return revision }
    public func isCurrent(_ candidate: UInt64) -> Bool { candidate == revision }
    public mutating func recordOwnWrite(id: UInt32, level: Double) { previous[id] = level }
    public mutating func observe(id: UInt32, level: Double) -> Bool {
        guard level.isFinite else { return false }
        guard let old = previous[id] else { previous[id] = level; return false }
        guard abs(old - level) > 0.004 else { return false }
        previous[id] = level
        return true
    }
    public mutating func invalidate() { revision &+= 1; previous.removeAll() }
}
