//
//  ScriptHighlightTheme.swift
//  Modules
//

import AppKit

/// Dynamic system colours, so highlighting adapts to light and dark mode.
enum ScriptHighlightTheme {
    static func color(for kind: ScriptTokenKind) -> NSColor {
        switch kind {
        case .keyword: .systemPink
        case .string: .systemRed
        case .comment: .secondaryLabelColor
        case .number: .systemPurple
        case .variable: .systemTeal
        }
    }

    static var font: NSFont {
        .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }
}
