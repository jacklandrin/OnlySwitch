public struct DDCReading: Equatable, Sendable {
    public let current: Int
    public let maximum: Int

    public init(current: Int, maximum: Int) {
        self.current = current
        self.maximum = maximum
    }

    /// The current value as `0...100`.
    public var percent: Int {
        guard maximum > 0 else { return 0 }
        return min(100, max(0, Int((Double(current) * 100 / Double(maximum)).rounded())))
    }

    /// The display value for `percent`, scaled to the display's own range.
    public static func value(forPercent percent: Int, maximum: Int) -> UInt16 {
        let clamped = min(100, max(0, percent))
        return UInt16(min(Int(UInt16.max), Int((Double(clamped) * Double(maximum) / 100).rounded())))
    }
}
