import Foundation

public enum DesktopPetSkinValidationError: Error, Equatable, Sendable {
    case empty
    case tooLarge
    case forbidden(String)
    case missingRoot
    case missingStates([String])

    /// A non-sensitive label for logs.
    public var category: String {
        switch self {
        case .empty: "empty"
        case .tooLarge: "tooLarge"
        case .forbidden: "forbidden"
        case .missingRoot: "missingRoot"
        case .missingStates: "missingStates"
        }
    }

    /// Feedback for the single repair round with the model.
    public var repairHint: String {
        switch self {
        case .empty: "The reply contained no markup."
        case .tooLarge: "The markup exceeds \(DesktopPetSkinContract.maximumMarkupBytes) bytes; simplify it."
        case let .forbidden(token): "The markup used forbidden content: \(token). Use only inline CSS and SVG/HTML shapes."
        case .missingRoot: "The root element must have id=\"pet\"."
        case let .missingStates(states): "Add CSS rules for these missing states: \(states.joined(separator: ", "))."
        }
    }
}

/// Static checks for an untrusted, model-written skin. The renderer's CSP and disabled JavaScript
/// are the real boundary; this rejects anything that could not work there and anything incomplete.
/// Patterns run on a copy with HTML character references and CSS escapes decoded, so encoded
/// forms such as `&#106;avascript:` or `u\72l(` are caught too.
public enum DesktopPetSkinValidator {
    private static let allowedNamespaces = [
        "xmlns=\"http://www.w3.org/2000/svg\"", "xmlns='http://www.w3.org/2000/svg'",
        "xmlns:xlink=\"http://www.w3.org/1999/xlink\"", "xmlns:xlink='http://www.w3.org/1999/xlink'",
    ]

    /// Case-insensitive patterns, run on the decoded markup, paired with the label reported to the model.
    private static let forbiddenPatterns: [(pattern: String, label: String)] = [
        (#"<\s*/?\s*(script|iframe|frame|frameset|portal|applet|object|embed|link|meta|base|form|input|button|textarea|select|html|head|body|foreignobject|audio|video|source|track)\b"#, "disallowed element"),
        (#"<\s*/?\s*a[\s/>]"#, "link element"),
        (#"[\s/"'`]on[a-z]+\s*="#, "event handler attribute"),
        (#"@import"#, "@import"),
        (#"@font-face"#, "@font-face"),
        (#"\bsrc\s*\("#, "src()"),
        (#"image-set\s*\("#, "image-set()"),
        (#"attributename\s*=\s*["']?\s*(xlink\s*:\s*)?(href|src)\b"#, "animated href"),
        (#"(href|src)\s*=\s*["']?\s*//"#, "protocol-relative URL"),
        (#"url\(\s*["']?\s*(?!#|data:image/)"#, "url() other than #id or data:image"),
        (#"(href|src|srcset|poster|background|action|formaction|ping|lowsrc)\s*=\s*["']?\s*(?!#|data:image/)[^"'\s>]"#, "href/src other than #id or data:image"),
    ]

    /// Run on the decoded markup with all whitespace and control characters removed, because URL
    /// parsers drop tabs and newlines inside a scheme.
    private static let forbiddenSchemePatterns: [(pattern: String, label: String)] = [
        (#"(java|vb)script:"#, "javascript: URL"),
        (#"\b(https?|file|ftp):"#, "external URL"),
    ]

    /// Named character references the scanner understands; any other one is rejected because it
    /// could hide punctuation such as `&colon;` or `&lpar;`.
    private static let allowedNamedReferences: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "hearts": "\u{2665}", "times": "\u{00D7}", "middot": "\u{00B7}", "hellip": "\u{2026}",
        "deg": "\u{00B0}", "copy": "\u{00A9}", "star": "\u{2606}", "bull": "\u{2022}",
    ]

    public static func validate(_ markup: String) throws(DesktopPetSkinValidationError) -> String {
        let trimmed = markup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard trimmed.utf8.count <= DesktopPetSkinContract.maximumMarkupBytes else { throw .tooLarge }

        var scanned = trimmed
        for namespace in allowedNamespaces {
            scanned = scanned.replacingOccurrences(of: namespace, with: " ", options: .caseInsensitive)
        }
        let decoded = decodeCSSEscapes(try decodeCharacterReferences(scanned))
        for (pattern, label) in forbiddenPatterns where matches(pattern, in: decoded) {
            throw .forbidden(label)
        }
        let compact = String(String.UnicodeScalarView(decoded.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0)
        }))
        for (pattern, label) in forbiddenSchemePatterns where matches(pattern, in: compact) {
            throw .forbidden(label)
        }
        guard matches(#"\bid\s*=\s*["']?pet["'\s>/]"#, in: trimmed) else { throw .missingRoot }

        let missing = DesktopPetSkinContract.requiredStates.filter { state in
            !matches(#"\[\s*data-state\s*=\s*["']?"# + state + #"["']?\s*\]"#, in: trimmed)
        }
        guard missing.isEmpty else { throw .missingStates(missing) }
        return trimmed
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Decodes numeric references (with or without `;`) and the allowlisted named ones.
    /// SVG `<style>` is foreign content, so references there reach the CSS parser decoded.
    static func decodeCharacterReferences(_ text: String) throws(DesktopPetSkinValidationError) -> String {
        guard text.contains("&") else { return text }
        let regex = try? NSRegularExpression(pattern: #"&(?:#[xX]([0-9a-fA-F]+);?|#([0-9]+);?|([A-Za-z][A-Za-z0-9]*);)"#)
        guard let regex else { throw .forbidden("character reference") }
        let source = text as NSString
        var result = ""
        var location = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            location = match.range.location + match.range.length
            if match.range(at: 3).location != NSNotFound {
                let name = source.substring(with: match.range(at: 3))
                guard let value = allowedNamedReferences[name] else { throw .forbidden("character reference &\(name);") }
                result += value
                continue
            }
            let hex = match.range(at: 1).location != NSNotFound
            let digits = source.substring(with: match.range(at: hex ? 1 : 2))
            let value = digits.count > 8 ? nil : UInt32(digits, radix: hex ? 16 : 10)
            result += value.flatMap(Unicode.Scalar.init).map(String.init) ?? "\u{FFFD}"
        }
        result += source.substring(from: location)
        return result
    }

    /// Decodes CSS escapes: `\` + 1–6 hex digits (+ one optional whitespace), or `\` + any other character.
    static func decodeCSSEscapes(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "\\", index + 1 < scalars.count else {
                result.append(scalar)
                index += 1
                continue
            }
            var end = index + 1
            var hex = ""
            while end < scalars.count, hex.count < 6, scalars[end].properties.isASCIIHexDigit {
                hex.unicodeScalars.append(scalars[end])
                end += 1
            }
            if hex.isEmpty {
                // `\` + newline is a line continuation inside CSS strings.
                if scalars[end] != "\n" { result.append(scalars[end]) }
                index = end + 1
                continue
            }
            result.append(UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init) ?? "\u{FFFD}")
            if end < scalars.count, [" ", "\t", "\n", "\r", "\u{0C}"].contains(scalars[end]) { end += 1 }
            index = end
        }
        return String(result)
    }
}
