import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum AphroditeIconExtractor {
    public static func extractValidatedSVG(from html: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)<template\b(?=[^>]*\bid\s*=\s*[\"']aphrodite-app-icon[\"'])[^>]*>\s*(<svg\b.*?</svg>)\s*</template>"#
        ), let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) else { return nil }
        return AphroditeSVGValidator.validated(String(html[range]))
    }
}

public enum AphroditeSVGValidator {
    public static let maximumBytes = 32_768

    public static func validated(_ svg: String) -> String? {
        let candidate = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.utf8.count <= maximumBytes,
              !candidate.contains("<!"), !candidate.contains("<?") else { return nil }
        let delegate = AphroditeSVGValidationDelegate()
        let parser = XMLParser(data: Data(candidate.utf8))
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.isValid ? candidate : nil
    }
}

private final class AphroditeSVGValidationDelegate: NSObject, XMLParserDelegate {
    private static let containers: Set<String> = ["svg", "g", "defs", "linearGradient", "radialGradient"]
    private static let shapes: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]
    private static let elements = containers.union(shapes).union(["stop"])
    private static let numericAttributes: Set<String> = ["width", "height", "x", "y", "rx", "ry", "cx", "cy", "r", "fx", "fy", "x1", "y1", "x2", "y2", "stroke-width"]
    private static let opacityAttributes: Set<String> = ["opacity", "fill-opacity", "stroke-opacity", "stop-opacity"]
    private static let numberPattern = #"[-+]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][-+]?\d+)?"#
    private static let idPattern = #"[A-Za-z_][A-Za-z0-9_.-]*"#
    private static let numberExpression = try! NSRegularExpression(pattern: numberPattern)

    private(set) var isValid = true
    private var depth = 0
    private var elementCount = 0
    private var visibleShapeCount = 0
    private var nonRenderingDepth = 0
    private var pathDataLength = 0
    private var numberCount = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributes: [String: String] = [:]) {
        guard isValid else { parser.abortParsing(); return }
        depth += 1
        elementCount += 1
        guard depth <= 64, elementCount <= 256, Self.elements.contains(elementName) else { reject(parser); return }
        if elementCount == 1 {
            guard elementName == "svg", attributes["xmlns"] == "http://www.w3.org/2000/svg",
                  let viewBox = attributes["viewBox"], validViewBox(viewBox) else { reject(parser); return }
        } else if elementName == "svg" {
            reject(parser); return
        }
        guard attributes.allSatisfy({ validAttribute(name: $0.key, value: $0.value, element: elementName, isRoot: elementCount == 1) }) else { reject(parser); return }
        if Self.shapes.contains(elementName), nonRenderingDepth == 0 { visibleShapeCount += 1 }
        if elementName == "defs" || elementName == "linearGradient" || elementName == "radialGradient" { nonRenderingDepth += 1 }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "defs" || elementName == "linearGradient" || elementName == "radialGradient" { nonRenderingDepth -= 1 }
        depth -= 1
    }

    func parserDidEndDocument(_ parser: XMLParser) { isValid = depth == 0 && visibleShapeCount > 0 }
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { isValid = false }
    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) { isValid = false }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) { reject(parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { reject(parser) }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { reject(parser) }

    private func validAttribute(name: String, value: String, element: String, isRoot: Bool) -> Bool {
        switch name {
        case "xmlns": return isRoot && value == "http://www.w3.org/2000/svg"
        case "viewBox": return isRoot && validViewBox(value)
        case "id": return matches(value, Self.idPattern)
        case let name where Self.numericAttributes.contains(name): return validNumber(value)
        case let name where Self.opacityAttributes.contains(name): return validUnitInterval(value)
        case "offset": return validOffset(value)
        case "fill", "stroke", "stop-color": return validPaint(value)
        case "stroke-linecap": return ["butt", "round", "square"].contains(value)
        case "stroke-linejoin": return ["miter", "round", "bevel"].contains(value)
        case "transform", "gradientTransform": return validTransform(value)
        case "gradientUnits": return ["objectBoundingBox", "userSpaceOnUse"].contains(value)
        case "spreadMethod": return ["pad", "reflect", "repeat"].contains(value)
        case "d": return element == "path" && validPath(value)
        case "points": return (element == "polyline" || element == "polygon") && validPoints(value)
        default: return false
        }
    }

    private func validViewBox(_ value: String) -> Bool {
        let values = parsedNumbers(value)
        return values.count == 4 && values.allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } && values[2] > 0 && values[3] > 0 && values[2] <= 512 && values[3] <= 512
    }
    private func validNumber(_ value: String) -> Bool { matches(value, Self.numberPattern) && parsedNumbers(value).first.map { $0.isFinite && abs($0) <= 1_000_000 } == true }
    private func validUnitInterval(_ value: String) -> Bool { validNumber(value) && parsedNumbers(value).first.map { (0...1).contains($0) } == true }
    private func validOffset(_ value: String) -> Bool {
        if value.hasSuffix("%"), let number = Double(value.dropLast()) { return number.isFinite && (0...100).contains(number) }
        return validUnitInterval(value)
    }
    private func validPaint(_ value: String) -> Bool {
        value == "none" || matches(value, #"#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})"#) || matches(value, #"url\(#[A-Za-z_][A-Za-z0-9_.-]*\)"#)
    }
    private func validTransform(_ value: String) -> Bool {
        let pattern = #"(?:(?:matrix|translate|scale|rotate)\(\s*"# + Self.numberPattern + #"(?:\s*(?:,|\s)\s*"# + Self.numberPattern + #"){0,5}\s*\)\s*)+"#
        return matches(value, pattern) && consumeNumbers(value, maximum: 24)
    }
    private func validPath(_ value: String) -> Bool {
        pathDataLength += value.utf8.count
        guard pathDataLength <= 16_384, matches(value, #"[MmLlHhVvCcSsQqTtAaZz][MmLlHhVvCcSsQqTtAaZz0-9,.+\-eE\s]*"#) else { return false }
        return consumeNumbers(value, maximum: 2_048)
    }
    private func validPoints(_ value: String) -> Bool {
        let values = parsedNumbers(value)
        guard values.count >= 4, values.count.isMultiple(of: 2), values.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return false }
        return consumeNumbers(value, maximum: 2_048)
    }
    private func consumeNumbers(_ value: String, maximum: Int) -> Bool {
        let matches = Self.numberExpression.matches(in: value, range: NSRange(value.startIndex..., in: value))
        let values = matches.compactMap { Range($0.range, in: value).flatMap { Double(value[$0]) } }
        guard values.count == matches.count,
              values.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return false }
        numberCount += values.count
        return values.count <= maximum && numberCount <= 2_048
    }
    private func parsedNumbers(_ value: String) -> [Double] {
        guard matches(value, #"(?:"# + Self.numberPattern + #")(?:[\s,]+"# + Self.numberPattern + #")*"#) else { return [] }
        return value.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Double($0) }
    }
    private func matches(_ value: String, _ pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: "^(?:\(pattern))$") else { return false }
        return expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
    private func reject(_ parser: XMLParser) { isValid = false; parser.abortParsing() }
}
