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
public enum DesktopPetSkinValidator {
    private static let allowedNamespaces = [
        "xmlns=\"http://www.w3.org/2000/svg\"", "xmlns='http://www.w3.org/2000/svg'",
        "xmlns:xlink=\"http://www.w3.org/1999/xlink\"", "xmlns:xlink='http://www.w3.org/1999/xlink'",
    ]

    /// Case-insensitive patterns paired with the label reported to the model.
    private static let forbiddenPatterns: [(pattern: String, label: String)] = [
        (#"<\s*/?\s*(script|iframe|object|embed|link|meta|base|form|input|button|textarea|select|html|head|body|foreignobject|audio|video|source|track)\b"#, "disallowed element"),
        (#"<\s*a[\s>]"#, "link element"),
        (#"\son[a-z]+\s*="#, "event handler attribute"),
        (#"javascript\s*:"#, "javascript: URL"),
        (#"@import"#, "@import"),
        (#"\b(https?|file|ftp)\s*:"#, "external URL"),
        (#"(href|src)\s*=\s*["']?\s*//"#, "protocol-relative URL"),
        (#"url\(\s*["']?(?!#|data:image/)"#, "url() other than #id or data:image"),
        (#"(href|src)\s*=\s*["']?(?!#|data:image/)[^"'\s>]"#, "href/src other than #id or data:image"),
    ]

    public static func validate(_ markup: String) throws(DesktopPetSkinValidationError) -> String {
        let trimmed = markup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard trimmed.utf8.count <= DesktopPetSkinContract.maximumMarkupBytes else { throw .tooLarge }

        var scanned = trimmed
        for namespace in allowedNamespaces {
            scanned = scanned.replacingOccurrences(of: namespace, with: "", options: .caseInsensitive)
        }
        for (pattern, label) in forbiddenPatterns where matches(pattern, in: scanned) {
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
}
