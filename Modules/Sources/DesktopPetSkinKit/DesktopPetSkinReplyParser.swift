import Foundation

public struct DesktopPetSkinDraft: Equatable, Sendable {
    public var name: String
    public var markup: String

    public init(name: String, markup: String) {
        self.name = name
        self.markup = markup
    }
}

public enum DesktopPetSkinReplyError: Error, Equatable, Sendable {
    case noMarkup
    case refused(String)
}

/// Tolerantly extracts `NAME:` and the first ```html block (or bare markup) from a model reply.
public enum DesktopPetSkinReplyParser {
    public static func parse(_ reply: String) throws(DesktopPetSkinReplyError) -> DesktopPetSkinDraft {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("ERROR:") {
            throw .refused(String(text.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let name = firstMatch(#"(?m)^\s*NAME:\s*(.+)$"#, in: text) ?? ""
        let markup = firstMatch(#"(?s)```(?:html)?\s*\n(.*?)```"#, in: text)
            ?? (text.contains("<style") || text.contains("id=\"pet\"") ? text : nil)
        guard let markup, !markup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .noMarkup }
        return DesktopPetSkinDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            markup: markup.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
