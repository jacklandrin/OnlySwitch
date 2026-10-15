import Foundation
import UniformTypeIdentifiers

public extension UTType {
    static let aphroditeMiniApp = UTType(exportedAs: "com.onlyswitch.aphrodite-mini-app", conformingTo: .json)
}

public struct AphroditeShareDocument: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let maximumTitleCharacters = 80
    // JSON may escape each UTF-8 byte as a six-byte `\uXXXX` sequence.
    public static let maximumEncodedBytes =
        (AphroditeHTMLExtractor.maximumDocumentBytes + AphroditeSVGValidator.maximumBytes + maximumTitleCharacters) * 6 + 4_096

    public enum ValidationError: Error, Equatable, Sendable {
        case documentTooLarge
        case malformedDocument
        case unsupportedVersion(Int)
        case invalidTitle
        case invalidHTML
        case invalidIcon
    }

    public let formatVersion: Int
    public let title: String
    public let html: String
    public let iconSVG: String?

    public init(formatVersion: Int = currentFormatVersion, title: String, html: String, iconSVG: String? = nil) throws {
        guard formatVersion == Self.currentFormatVersion else { throw ValidationError.unsupportedVersion(formatVersion) }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, normalizedTitle.count <= Self.maximumTitleCharacters else { throw ValidationError.invalidTitle }
        guard !html.isEmpty, html.utf8.count <= AphroditeHTMLExtractor.maximumDocumentBytes,
              let validatedHTML = try? AphroditeHTMLExtractor.extract(html) else { throw ValidationError.invalidHTML }
        if let iconSVG, AphroditeSVGValidator.validated(iconSVG) == nil { throw ValidationError.invalidIcon }
        self.formatVersion = formatVersion
        self.title = normalizedTitle
        self.html = validatedHTML
        self.iconSVG = iconSVG
    }

    public init(app: AphroditeApp) {
        formatVersion = Self.currentFormatVersion
        let normalizedTitle = app.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = String((normalizedTitle.isEmpty ? "Mini App" : normalizedTitle).prefix(Self.maximumTitleCharacters))
        html = app.html
        iconSVG = app.iconSVG.flatMap(AphroditeSVGValidator.validated)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumEncodedBytes else { throw ValidationError.documentTooLarge }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch let error as ValidationError { throw error }
        catch { throw ValidationError.malformedDocument }
    }

    public func encoded() throws -> Data {
        _ = try Self(formatVersion: formatVersion, title: title, html: html, iconSVG: iconSVG)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else { throw ValidationError.documentTooLarge }
        return data
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, title, html, iconSVG }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            formatVersion: values.decode(Int.self, forKey: .formatVersion),
            title: values.decode(String.self, forKey: .title),
            html: values.decode(String.self, forKey: .html),
            iconSVG: values.decodeIfPresent(String.self, forKey: .iconSVG)
        )
    }
}
