import Foundation

struct RemoteControlAvailability: Equatable, Sendable {
    let isAvailable: Bool
    let reason: String?

    static let available = Self(isAvailable: true, reason: nil)

    static func unavailable(_ reason: String) -> Self {
        Self(isAvailable: false, reason: reason)
    }
}
