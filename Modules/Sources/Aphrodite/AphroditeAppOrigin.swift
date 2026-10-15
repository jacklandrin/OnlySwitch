import Foundation

public struct AphroditeAppOrigin: Equatable, Hashable, Sendable {
    public static let scheme = "aphrodite-mini-app"

    public let appID: UUID

    public init(appID: UUID) {
        self.appID = appID
    }

    public var indexURL: URL {
        URL(string: "\(Self.scheme)://app-\(appID.uuidString.lowercased())/index.html")!
    }
}
