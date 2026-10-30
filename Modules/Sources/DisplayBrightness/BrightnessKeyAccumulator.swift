/// A requested keyboard target and its unique completion token.
public struct BrightnessKeyAdjustment: Equatable, Sendable {
    public let level: Double
    public let revision: UInt64

    public init(level: Double, revision: UInt64) {
        self.level = level
        self.revision = revision
    }
}

/// Accumulates repeats synchronously, before asynchronous hardware writes can complete.
/// The owning service isolates this value with its other brightness intent state.
public struct BrightnessKeyAccumulator: Sendable {
    private var pending: [UInt32: BrightnessKeyAdjustment] = [:]
    private var revision: UInt64 = 0

    public init() {}

    public mutating func next(screenID: UInt32, current: Double, key: BrightnessKeyEvent.Key,
                              fine: Bool) -> BrightnessKeyAdjustment {
        revision &+= 1
        let level = BrightnessKeyPolicy.level(current: pending[screenID]?.level ?? current, key: key, fine: fine)
        let adjustment = BrightnessKeyAdjustment(level: level, revision: revision)
        pending[screenID] = adjustment
        return adjustment
    }

    public mutating func finish(screenID: UInt32, revision: UInt64) {
        guard pending[screenID]?.revision == revision else { return }
        pending[screenID] = nil
    }

    public mutating func cancel(screenID: UInt32) {
        pending[screenID] = nil
    }

    public mutating func reset() {
        pending.removeAll()
        // Keep revisions monotonic so an old completion cannot match a replacement screen.
    }
}
