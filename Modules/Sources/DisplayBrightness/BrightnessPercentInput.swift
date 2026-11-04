import Foundation

/// Converts a typed brightness percent to a 0...1 level; out-of-range numbers are clamped, anything else is rejected.
public enum BrightnessPercentInput {
    public static func level(from text: String, locale: Locale = .current) -> Double? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("%") { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        if let separator = locale.decimalSeparator, separator != "." {
            text = text.replacingOccurrences(of: separator, with: ".")
        }
        // Plain digits only, so "inf", "nan", exponents and grouping separators never reach Double().
        let digits = text.hasPrefix("-") || text.hasPrefix("+") ? text.dropFirst() : Substring(text)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              digits.filter({ $0 == "." }).count <= 1, digits.contains(where: \.isNumber),
              let percent = Double(text), percent.isFinite else { return nil }
        return min(100, max(0, percent)) / 100
    }

    public static func text(for level: Double) -> String {
        String(Int((min(1, max(0, level)) * 100).rounded()))
    }
}
