/// Tracks observed native changes separately from our own writes and invalidates overlapping sync passes.
public struct BrightnessNativeSyncState: Sendable {
    private static let tolerance = 0.004
    private var revision: UInt64 = 0
    private var previous: [UInt32: Double] = [:]
    private var expectedReadbacks: [UInt32: Double] = [:]
    public init() {}
    public mutating func beginCycle() -> UInt64 { revision &+= 1; return revision }
    public func isCurrent(_ candidate: UInt64) -> Bool { candidate == revision }
    public mutating func recordOwnWrite(id: UInt32, level: Double, readback: Double? = nil) {
        let sampled = readback ?? level
        previous[id] = sampled
        // A read immediately after Set may still report the old value. Accept the requested
        // value as our own echo on the next poll too, without masking later user changes.
        expectedReadbacks[id] = abs(sampled - level) > Self.tolerance ? level : nil
    }
    public mutating func observe(id: UInt32, level: Double) -> Bool {
        guard level.isFinite else { return false }
        let expected = expectedReadbacks.removeValue(forKey: id)
        guard let old = previous[id] else { previous[id] = level; return false }
        guard abs(old - level) > Self.tolerance else { return false }
        previous[id] = level
        return expected.map { abs($0 - level) > Self.tolerance } ?? true
    }

    public mutating func observeChanges(
        _ readings: [(display: BrightnessDisplay, level: Double)]
    ) -> (id: UInt32, level: Double)? {
        let changes = readings.filter {
            $0.display.control == .native && observe(id: $0.display.id, level: $0.level)
        }
        return Self.preferredSource(in: changes)
    }

    public static func preferredSource(
        in readings: [(display: BrightnessDisplay, level: Double)]
    ) -> (id: UInt32, level: Double)? {
        let source = readings.lazy.filter { $0.display.control == .native && $0.level.isFinite }.min {
            if $0.display.isBuiltIn != $1.display.isBuiltIn { return $0.display.isBuiltIn }
            return $0.display.id < $1.display.id
        }
        return source.map { ($0.display.id, $0.level) }
    }

    public static func targets(in displays: [BrightnessDisplay], excluding sourceID: UInt32) -> [BrightnessDisplay] {
        displays.filter { !$0.isBuiltIn && $0.id != sourceID && $0.control != .unavailable }
    }

    public mutating func invalidate() {
        revision &+= 1
        previous.removeAll()
        expectedReadbacks.removeAll()
    }
}
