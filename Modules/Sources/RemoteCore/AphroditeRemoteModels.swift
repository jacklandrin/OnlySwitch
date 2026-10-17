import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum AphroditeRemoteHTMLValidator {
    public static let maximumDocumentBytes = 1_048_576
    public static func validated(_ html: String) -> String? {
        guard html.utf8.count <= maximumDocumentBytes else { return nil }
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(pattern: #"(?is)^\s*(?:<!doctype\s+html[^>]*>\s*)?<html\b[^>]*>.*</html>\s*$"#),
              expression.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else { return nil }
        return trimmed
    }
}

public enum AphroditeRemoteSVGValidator {
    public static let maximumBytes = 32_768
    public static func validated(_ svg: String) -> String? {
        let candidate = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.isEmpty == false, candidate.utf8.count <= maximumBytes,
              candidate.contains("<!") == false, candidate.contains("<?") == false else { return nil }
        let delegate = AphroditeRemoteSVGValidationDelegate()
        let parser = XMLParser(data: Data(candidate.utf8))
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.isValid ? candidate : nil
    }
}

private final class AphroditeRemoteSVGValidationDelegate: NSObject, XMLParserDelegate {
    private static let containers: Set<String> = ["svg", "g", "defs", "linearGradient", "radialGradient"]
    private static let shapes: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]
    private static let elements = containers.union(shapes).union(["stop"])
    private static let numericAttributes: Set<String> = ["width", "height", "x", "y", "rx", "ry", "cx", "cy", "r", "fx", "fy", "x1", "y1", "x2", "y2", "stroke-width"]
    private static let opacityAttributes: Set<String> = ["opacity", "fill-opacity", "stroke-opacity", "stop-opacity"]
    private static let numberPattern = #"[-+]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][-+]?\d+)?"#
    private static let idPattern = #"[A-Za-z_][A-Za-z0-9_.-]*"#
    private static let numberExpression = try! NSRegularExpression(pattern: numberPattern)
    private(set) var isValid = true
    private var depth = 0, elementCount = 0, visibleShapeCount = 0, nonRenderingDepth = 0, pathDataLength = 0, numberCount = 0

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        guard isValid else { parser.abortParsing(); return }
        depth += 1; elementCount += 1
        guard depth <= 64, elementCount <= 256, Self.elements.contains(name) else { reject(parser); return }
        if elementCount == 1 {
            guard name == "svg", attributes["xmlns"] == "http://www.w3.org/2000/svg", attributes["viewBox"].map(validViewBox) == true else { reject(parser); return }
        } else if name == "svg" { reject(parser); return }
        guard attributes.allSatisfy({ validAttribute(name: $0.key, value: $0.value, element: name, isRoot: elementCount == 1) }) else { reject(parser); return }
        if Self.shapes.contains(name), nonRenderingDepth == 0 { visibleShapeCount += 1 }
        if ["defs", "linearGradient", "radialGradient"].contains(name) { nonRenderingDepth += 1 }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if ["defs", "linearGradient", "radialGradient"].contains(name) { nonRenderingDepth -= 1 }; depth -= 1
    }
    func parserDidEndDocument(_ parser: XMLParser) { isValid = depth == 0 && visibleShapeCount > 0 }
    func parser(_ parser: XMLParser, parseErrorOccurred: Error) { isValid = false }
    func parser(_ parser: XMLParser, validationErrorOccurred: Error) { isValid = false }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget: String, data: String?) { reject(parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName: String, publicID: String?, systemID: String?) { reject(parser) }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName: String, value: String?) { reject(parser) }
    private func validAttribute(name: String, value: String, element: String, isRoot: Bool) -> Bool {
        switch name {
        case "xmlns": isRoot && value == "http://www.w3.org/2000/svg"
        case "viewBox": isRoot && validViewBox(value)
        case "id": matches(value, Self.idPattern)
        case let key where Self.numericAttributes.contains(key): validNumber(value)
        case let key where Self.opacityAttributes.contains(key): validNumber(value) && (parsedNumbers(value).first.map { (0...1).contains($0) } ?? false)
        case "offset": value.hasSuffix("%") ? (Double(value.dropLast()).map { (0...100).contains($0) } ?? false) : (validNumber(value) && (parsedNumbers(value).first.map { (0...1).contains($0) } ?? false))
        case "fill", "stroke", "stop-color": value == "none" || matches(value, #"#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})"#) || matches(value, #"url\(#[A-Za-z_][A-Za-z0-9_.-]*\)"#)
        case "stroke-linecap": ["butt", "round", "square"].contains(value)
        case "stroke-linejoin": ["miter", "round", "bevel"].contains(value)
        case "transform", "gradientTransform": matches(value, #"(?:(?:matrix|translate|scale|rotate)\(\s*"# + Self.numberPattern + #"(?:\s*(?:,|\s)\s*"# + Self.numberPattern + #"){0,5}\s*\)\s*)+"#) && consumeNumbers(value, maximum: 24)
        case "gradientUnits": ["objectBoundingBox", "userSpaceOnUse"].contains(value)
        case "spreadMethod": ["pad", "reflect", "repeat"].contains(value)
        case "d": element == "path" && validPath(value)
        case "points": (element == "polyline" || element == "polygon") && validPoints(value)
        default: false
        }
    }
    private func validViewBox(_ value: String) -> Bool { let v = parsedNumbers(value); return v.count == 4 && v.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } && v[2] > 0 && v[3] > 0 && v[2] <= 512 && v[3] <= 512 }
    private func validNumber(_ value: String) -> Bool { matches(value, Self.numberPattern) && (parsedNumbers(value).first.map { $0.isFinite && abs($0) <= 1_000_000 } ?? false) }
    private func validPath(_ value: String) -> Bool { pathDataLength += value.utf8.count; return pathDataLength <= 16_384 && matches(value, #"[MmLlHhVvCcSsQqTtAaZz][MmLlHhVvCcSsQqTtAaZz0-9,.+\-eE\s]*"#) && consumeNumbers(value, maximum: 2_048) }
    private func validPoints(_ value: String) -> Bool { let v = parsedNumbers(value); return v.count >= 4 && v.count.isMultiple(of: 2) && v.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } && consumeNumbers(value, maximum: 2_048) }
    private func consumeNumbers(_ value: String, maximum: Int) -> Bool { let m = Self.numberExpression.matches(in: value, range: NSRange(value.startIndex..., in: value)); let v = m.compactMap { Range($0.range, in: value).flatMap { Double(value[$0]) } }; guard v.count == m.count, v.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return false }; numberCount += v.count; return v.count <= maximum && numberCount <= 2_048 }
    private func parsedNumbers(_ value: String) -> [Double] { guard matches(value, #"(?:"# + Self.numberPattern + #")(?:[\s,]+"# + Self.numberPattern + #")*"#) else { return [] }; return value.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Double($0) } }
    private func matches(_ value: String, _ pattern: String) -> Bool { (try? NSRegularExpression(pattern: "^(?:\(pattern))$").firstMatch(in: value, range: NSRange(value.startIndex..., in: value))) != nil }
    private func reject(_ parser: XMLParser) { isValid = false; parser.abortParsing() }
}

public enum AphroditeRemoteValidationError: Error, Equatable, Sendable {
    case invalidTitle
    case invalidHTML
    case invalidIcon
    case invalidDescriptor
    case duplicateAppID
    case invalidChunk
    case snapshotTooLarge
    case unsupportedFormatVersion
}

public struct AphroditePersonalTool: Codable, Equatable, Identifiable, Sendable {
    public static let currentFormatVersion = 1
    public static let maximumHTMLBytes = 1_048_576
    public static let maximumIconBytes = 131_072
    public static let maximumTitleCharacters = 80

    public let id: UUID
    public let title: String
    public let html: String
    public let iconSVG: String?
    public let updatedAt: Date
    public let formatVersion: Int

    public init(id: UUID, title: String, html: String, iconSVG: String? = nil, updatedAt: Date) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, title.count <= Self.maximumTitleCharacters else {
            throw AphroditeRemoteValidationError.invalidTitle
        }
        guard html.utf8.count <= Self.maximumHTMLBytes,
              let html = AphroditeRemoteHTMLValidator.validated(html) else {
            throw AphroditeRemoteValidationError.invalidHTML
        }
        let validatedIcon = iconSVG.flatMap(AphroditeRemoteSVGValidator.validated)
        if iconSVG != nil, validatedIcon == nil {
            throw AphroditeRemoteValidationError.invalidIcon
        }
        self.id = id
        self.title = title
        self.html = html
        self.iconSVG = validatedIcon
        self.updatedAt = updatedAt
        self.formatVersion = Self.currentFormatVersion
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .formatVersion) == Self.currentFormatVersion else {
            throw AphroditeRemoteValidationError.unsupportedFormatVersion
        }
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            title: values.decode(String.self, forKey: .title),
            html: values.decode(String.self, forKey: .html),
            iconSVG: values.decodeIfPresent(String.self, forKey: .iconSVG),
            updatedAt: values.decode(Date.self, forKey: .updatedAt)
        )
    }

}

public struct AphroditeRemoteLibrarySnapshot: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let apps: [AphroditePersonalTool]

    public init(revision: UInt64, apps: [AphroditePersonalTool]) {
        self.revision = revision
        self.apps = apps
    }

    public func validated() throws -> Self {
        guard Set(apps.map(\.id)).count == apps.count else {
            throw AphroditeRemoteValidationError.duplicateAppID
        }
        guard apps.count <= AphroditeRemoteLibraryManifest.maximumDocumentCount else {
            throw AphroditeRemoteValidationError.snapshotTooLarge
        }
        let encoder = JSONEncoder()
        var byteCount = 0
        for app in apps {
            byteCount += try encoder.encode(app).count
            guard byteCount <= AphroditeRemoteLibraryManifest.maximumTotalBytes else {
                throw AphroditeRemoteValidationError.snapshotTooLarge
            }
        }
        return self
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self(
            revision: values.decode(UInt64.self, forKey: .revision),
            apps: values.decode([AphroditePersonalTool].self, forKey: .apps)
        ).validated()
    }
}

public struct AphroditeRemoteDocumentDescriptor: Codable, Equatable, Sendable {
    public static let maximumChunkBytes = 65_536
    public static let maximumDocumentBytes = 8 * 1_048_576

    public let appID: UUID
    public let title: String
    public let updatedAt: Date
    public let byteCount: Int
    public let chunkCount: Int
    public let sha256: Data

    public init(appID: UUID, title: String, updatedAt: Date, byteCount: Int, chunkCount: Int, sha256: Data) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, title.count <= AphroditePersonalTool.maximumTitleCharacters,
              byteCount > 0, byteCount <= Self.maximumDocumentBytes,
              chunkCount > 0,
              chunkCount == (byteCount + Self.maximumChunkBytes - 1) / Self.maximumChunkBytes,
              sha256.count == 32 else { throw AphroditeRemoteValidationError.invalidDescriptor }
        self.appID = appID
        self.title = title
        self.updatedAt = updatedAt
        self.byteCount = byteCount
        self.chunkCount = chunkCount
        self.sha256 = sha256
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(appID: values.decode(UUID.self, forKey: .appID), title: values.decode(String.self, forKey: .title), updatedAt: values.decode(Date.self, forKey: .updatedAt), byteCount: values.decode(Int.self, forKey: .byteCount), chunkCount: values.decode(Int.self, forKey: .chunkCount), sha256: values.decode(Data.self, forKey: .sha256))
    }
}

public struct AphroditeRemoteLibraryManifest: Codable, Equatable, Sendable {
    public static let maximumDocumentCount = 128
    public static let maximumTotalBytes = 8 * 1_048_576
    public let revision: UInt64
    public let transferID: UUID
    public let documents: [AphroditeRemoteDocumentDescriptor]

    public init(revision: UInt64, transferID: UUID, documents: [AphroditeRemoteDocumentDescriptor]) throws {
        guard Set(documents.map(\.appID)).count == documents.count else {
            throw AphroditeRemoteValidationError.duplicateAppID
        }
        guard documents.count <= Self.maximumDocumentCount,
              documents.reduce(0, { $0 + $1.byteCount }) <= Self.maximumTotalBytes else {
            throw AphroditeRemoteValidationError.snapshotTooLarge
        }
        self.revision = revision
        self.transferID = transferID
        self.documents = documents
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(revision: values.decode(UInt64.self, forKey: .revision), transferID: values.decode(UUID.self, forKey: .transferID), documents: values.decode([AphroditeRemoteDocumentDescriptor].self, forKey: .documents))
    }
}

public struct AphroditeRemoteDocumentChunk: Codable, Equatable, Sendable {
    public let transferID: UUID
    public let appID: UUID
    public let index: Int
    public let data: Data

    public init(transferID: UUID, appID: UUID, index: Int, data: Data) throws {
        guard index >= 0, data.isEmpty == false, data.count <= AphroditeRemoteDocumentDescriptor.maximumChunkBytes else {
            throw AphroditeRemoteValidationError.invalidChunk
        }
        self.transferID = transferID
        self.appID = appID
        self.index = index
        self.data = data
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(transferID: values.decode(UUID.self, forKey: .transferID), appID: values.decode(UUID.self, forKey: .appID), index: values.decode(Int.self, forKey: .index), data: values.decode(Data.self, forKey: .data))
    }
}

public struct AphroditeRemoteAppOrigin: Equatable, Hashable, Sendable {
    public static let scheme = "aphrodite-personal-tool"
    public let appID: UUID
    public init(appID: UUID) { self.appID = appID }
    public var indexURL: URL { URL(string: "\(Self.scheme)://app-\(appID.uuidString.lowercased())/index.html")! }
}

public enum AphroditeRemoteSandboxDocument {
    public static let wrapperBaseURL = URL(string: "\(AphroditeRemoteAppOrigin.scheme)://wrapper/")!
    public static let contentSecurityPolicy = "default-src 'none'; connect-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action 'none'; base-uri 'none'; object-src 'none'; worker-src 'none'; frame-src 'none'"
    public static func make(origin: AphroditeRemoteAppOrigin) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; frame-src \(AphroditeRemoteAppOrigin.scheme):; style-src 'unsafe-inline'; base-uri 'none'; object-src 'none'">
        <style>html,body,iframe{width:100%;height:100%;margin:0;border:0;background:transparent}</style></head>
        <body><iframe sandbox="allow-scripts allow-same-origin" src="\(origin.indexURL.absoluteString)"></iframe></body></html>
        """
    }
}
