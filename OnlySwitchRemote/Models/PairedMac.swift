import Foundation

struct PairedMac: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var lastEndpointDescription: String?
    var lastConnectedAt: Date?
    var requiresPairing: Bool
}
