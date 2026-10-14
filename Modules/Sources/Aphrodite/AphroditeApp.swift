import Foundation
import OnlyAgent

public struct AphroditeApp: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var html: String
    public var iconSVG: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, title: String, html: String, iconSVG: String? = nil, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.html = html
        self.iconSVG = iconSVG.flatMap(AphroditeSVGValidator.validated)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case id, title, html, iconSVG, createdAt, updatedAt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        html = try values.decode(String.self, forKey: .html)
        iconSVG = try values.decodeIfPresent(String.self, forKey: .iconSVG).flatMap(AphroditeSVGValidator.validated)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
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
    public static let maximumDocumentBytes = 1_048_576

    public enum Error: Swift.Error, Equatable {
        case missingCompleteDocument
        case documentTooLarge
    }

    public static func extract(_ response: String) throws -> String {
        guard response.utf8.count <= maximumDocumentBytes else { throw Error.documentTooLarge }
        let candidate = fencedDocument(in: response) ?? response
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)^\s*(?:<!doctype\s+html[^>]*>\s*)?<html\b[^>]*>.*</html>\s*$"#
        ), expression.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else {
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
