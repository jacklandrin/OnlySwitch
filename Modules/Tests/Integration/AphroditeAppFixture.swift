import Foundation

public struct AphroditeApp: Equatable {
    public let id: UUID
    public let html: String

    public init(id: UUID, html: String) {
        self.id = id
        self.html = html
    }
}
