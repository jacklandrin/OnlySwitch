import Foundation

public struct RemoteControlStatus: Codable, Equatable, Identifiable, Sendable {
    public let id: RemoteControlID
    public let isAvailable: Bool
    public let unavailableReason: String?
    public let isOn: Bool?
    public let secondaryInformation: String?
    public let isProcessing: Bool
    public let revision: UInt64
    public let updatedAt: Date

    public init(
        id: RemoteControlID,
        isAvailable: Bool,
        unavailableReason: String?,
        isOn: Bool?,
        secondaryInformation: String?,
        isProcessing: Bool,
        revision: UInt64,
        updatedAt: Date
    ) {
        self.id = id
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
        self.isOn = isOn
        self.secondaryInformation = secondaryInformation
        self.isProcessing = isProcessing
        self.revision = revision
        self.updatedAt = updatedAt
    }
}
