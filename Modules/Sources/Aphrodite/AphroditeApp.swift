import Foundation
import OnlyAgent
import RemoteCore

public struct AphroditeApp: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var html: String
    public var iconSVG: String?
    public var conversationID: UUID
    public var conversation: [AphroditeConversationTurn]
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, title: String, html: String, iconSVG: String? = nil, createdAt: Date, updatedAt: Date, conversationID: UUID? = nil, conversation: [AphroditeConversationTurn] = []) {
        self.id = id
        self.title = title
        self.html = html
        self.iconSVG = iconSVG.flatMap(AphroditeSVGValidator.validated)
        self.conversationID = conversationID ?? id
        self.conversation = conversation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case id, title, html, iconSVG, createdAt, updatedAt, conversationID, conversation }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        html = try values.decode(String.self, forKey: .html)
        iconSVG = try values.decodeIfPresent(String.self, forKey: .iconSVG).flatMap(AphroditeSVGValidator.validated)
        conversationID = try values.decodeIfPresent(UUID.self, forKey: .conversationID) ?? id
        conversation = try values.decodeIfPresent([AphroditeConversationTurn].self, forKey: .conversation) ?? []
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}

public struct AphroditeConversationTurn: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let prompt: String
    public let createdAt: Date
    public init(id: UUID, prompt: String, createdAt: Date) { self.id = id; self.prompt = prompt; self.createdAt = createdAt }
}

public struct AphroditeModelSelection: Codable, Equatable, Sendable {
    public var provider: ModelProvider
    public var model: String

    public init(provider: ModelProvider, model: String) {
        self.provider = provider
        self.model = model
    }
}

public struct AphroditeLibrary: Codable, Equatable, Sendable {
    public var apps: [AphroditeApp]
    public var selection: AphroditeModelSelection?

    public init(apps: [AphroditeApp] = [], selection: AphroditeModelSelection? = nil) {
        self.apps = apps
        self.selection = selection
    }
}

public enum AphroditeHTMLExtractor {
    public static let maximumDocumentBytes = AphroditeRemoteHTMLValidator.maximumDocumentBytes

    public enum Error: Swift.Error, Equatable {
        case missingCompleteDocument
        case documentTooLarge
    }

    public static func extract(_ response: String) throws -> String {
        guard response.utf8.count <= maximumDocumentBytes else { throw Error.documentTooLarge }
        let candidate = fencedDocument(in: response) ?? response
        guard let trimmed = AphroditeRemoteHTMLValidator.validated(candidate) else {
            throw Error.missingCompleteDocument
        }
        return trimmed
    }

    private static func fencedDocument(in response: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #"(?is)```(?:html)?\s*(.*?)\s*```"#),
              let match = expression.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range(at: 1), in: response) else { return nil }
        return String(response[range])
    }
}
