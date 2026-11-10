//
//  ScriptTokenizer.swift
//  Modules
//

import Foundation

/// A small, forgiving lexer for syntax highlighting shell and AppleScript.
///
/// It never fails: unterminated strings and comments run to the end of the
/// text, and anything it doesn't recognise is left unhighlighted.
public enum ScriptTokenizer {
    static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
        "case", "esac", "in", "function", "return", "export", "local", "readonly",
        "echo", "exit", "sudo", "osascript", "defaults", "killall", "open", "source"
    ]

    static let appleScriptKeywords: Set<String> = [
        "tell", "end", "to", "of", "set", "get", "if", "then", "else", "repeat",
        "with", "without", "return", "try", "on", "error", "true", "false",
        "application", "do", "shell", "script", "display", "dialog", "notification",
        "activate", "quit", "delay", "run", "is", "not", "and", "or", "my", "it",
        "every", "whose", "times", "from", "contains", "as", "the", "exit", "considering",
        "ignoring", "using", "terms", "property", "global", "local", "me"
    ]

    private static let newline: UInt16 = 10
    private static let backslash: UInt16 = 92
    private static let hash: UInt16 = 35
    private static let doubleQuote: UInt16 = 34
    private static let singleQuote: UInt16 = 39
    private static let dollar: UInt16 = 36
    private static let dash: UInt16 = 45
    private static let openParen: UInt16 = 40
    private static let closeParen: UInt16 = 41
    private static let asterisk: UInt16 = 42
    private static let openBrace: UInt16 = 123
    private static let closeBrace: UInt16 = 125

    public static func tokens(in text: String, language: ScriptLanguage) -> [ScriptToken] {
        let units = Array(text.utf16)
        let keywords = language == .shell ? shellKeywords : appleScriptKeywords
        var tokens: [ScriptToken] = []
        var index = 0

        func emit(_ kind: ScriptTokenKind, _ start: Int, _ end: Int) {
            tokens.append(ScriptToken(kind: kind, range: NSRange(location: start, length: end - start)))
        }

        while index < units.count {
            let unit = units[index]
            let next: UInt16? = index + 1 < units.count ? units[index + 1] : nil

            if startsLineComment(units, at: index, language: language) {
                let end = lineEnd(units, from: index)
                emit(.comment, index, end)
                index = end
                continue
            }

            if language == .applescript, unit == openParen, next == asterisk {
                let end = blockCommentEnd(units, from: index)
                emit(.comment, index, end)
                index = end
                continue
            }

            if unit == doubleQuote || (language == .shell && unit == singleQuote) {
                let end = stringEnd(units, from: index, quote: unit, allowsEscapes: unit == doubleQuote)
                emit(.string, index, end)
                index = end
                continue
            }

            if language == .shell, unit == dollar, let end = variableEnd(units, from: index) {
                emit(.variable, index, end)
                index = end
                continue
            }

            if isWordUnit(unit) {
                var end = index
                while end < units.count, isWordUnit(units[end]) { end += 1 }
                let word = String(decoding: units[index..<end], as: UTF16.self)
                if word.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
                    emit(.number, index, end)
                } else if keywords.contains(language == .shell ? word : word.lowercased()) {
                    emit(.keyword, index, end)
                }
                index = end
                continue
            }

            index += 1
        }
        return tokens
    }

    private static func isWordUnit(_ unit: UInt16) -> Bool {
        (unit >= 48 && unit <= 57) || (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || unit == 95
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 32 || unit == 9 || unit == 10 || unit == 13
    }

    private static func startsLineComment(_ units: [UInt16], at index: Int, language: ScriptLanguage) -> Bool {
        let unit = units[index]
        switch language {
        case .shell:
            // `#` only starts a comment at the beginning of a word (`$#`, `a#b` are not comments).
            guard unit == hash else { return false }
            guard index > 0 else { return true }
            let previous = units[index - 1]
            return isWhitespace(previous) || previous == 59 /* ; */
        case .applescript:
            if unit == hash { return true }
            return unit == dash && index + 1 < units.count && units[index + 1] == dash
        }
    }

    private static func lineEnd(_ units: [UInt16], from start: Int) -> Int {
        var end = start
        while end < units.count, units[end] != newline { end += 1 }
        return end
    }

    private static func blockCommentEnd(_ units: [UInt16], from start: Int) -> Int {
        var end = start + 2
        while end + 1 < units.count {
            if units[end] == asterisk, units[end + 1] == closeParen { return end + 2 }
            end += 1
        }
        return units.count
    }

    private static func stringEnd(_ units: [UInt16], from start: Int, quote: UInt16, allowsEscapes: Bool) -> Int {
        var end = start + 1
        while end < units.count {
            if allowsEscapes, units[end] == backslash {
                end += 2
                continue
            }
            if units[end] == quote { return end + 1 }
            end += 1
        }
        return units.count
    }

    private static func variableEnd(_ units: [UInt16], from start: Int) -> Int? {
        guard start + 1 < units.count else { return nil }
        var end = start + 1
        if units[end] == openBrace {
            while end < units.count, units[end] != closeBrace { end += 1 }
            return min(end + 1, units.count)
        }
        while end < units.count, isWordUnit(units[end]) { end += 1 }
        return end > start + 1 ? end : nil
    }
}
