import Foundation

public struct DesktopPetSkin: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// The user's description, kept so the skin can be regenerated. Never logged.
    public var summary: String
    public var createdAt: Date
    public var contractVersion: Int
    public var markup: String

    public init(id: UUID, name: String, summary: String, createdAt: Date, contractVersion: Int, markup: String) {
        self.id = id
        self.name = name
        self.summary = summary
        self.createdAt = createdAt
        self.contractVersion = contractVersion
        self.markup = markup
    }
}
