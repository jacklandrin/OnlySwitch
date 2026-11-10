//
//  ScriptToken.swift
//  Modules
//

import Foundation

public enum ScriptTokenKind: Sendable, Equatable {
    case keyword
    case string
    case comment
    case number
    case variable
}

/// A highlighted span. `range` is in UTF-16 units so it can be applied to an
/// `NSTextStorage` directly.
public struct ScriptToken: Equatable, Sendable {
    public let kind: ScriptTokenKind
    public let range: NSRange

    public init(kind: ScriptTokenKind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}
