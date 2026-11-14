import Foundation

/// The pet's hunger, derived from the wall clock rather than a ticking counter, so sleep,
/// relaunches and long absences can never desynchronize it.
public struct DesktopPetNeeds: Equatable, Codable, Sendable {
    public static let hungerInterval: TimeInterval = 4 * 60 * 60

    public var lastFedAt: Date

    public init(lastFedAt: Date) {
        self.lastFedAt = lastFedAt
    }

    public func isHungry(at now: Date) -> Bool {
        now.timeIntervalSince(min(lastFedAt, now)) >= Self.hungerInterval
    }

    /// A meal dated in the future (the clock moved back) is treated as eaten now.
    public func normalized(at now: Date) -> Self {
        lastFedAt > now ? Self(lastFedAt: now) : self
    }

    public mutating func feed(at now: Date) {
        lastFedAt = now
    }
}
