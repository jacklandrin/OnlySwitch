import Foundation
import RemoteCore
import SwiftUI

enum RemoteClaudeUsageLayout {
    static func columnCount(availableWidth: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> Int {
        horizontalSizeClass == .regular && availableWidth >= 700 ? 2 : 1
    }
}

enum RemoteClaudeUsagePresentation {
    /// Same Claude logo as the Claude Usage tab in OnlySwitch.
    static let tabImageName = "claude_logo"
    static func percentage(_ quota: ClaudeQuotaWindowDTO?) -> String {
        quota.map { "\($0.remainingPercent)%" } ?? String(localized: "Unavailable")
    }
    static func extra(_ value: ClaudeExtraUsageDTO?) -> String {
        guard let value else { return String(localized: "Extra usage information is unavailable.") }
        guard value.isEnabled else { return String(localized: "Extra usage is disabled.") }
        let used = value.used.map { $0.formatted(.number.precision(.fractionLength(0 ... 2))) } ?? String(localized: "Unavailable")
        let limit = value.limit.map { " / " + $0.formatted(.number.precision(.fractionLength(0 ... 2))) } ?? ""
        return used + limit + (value.currency.map { " " + $0 } ?? "")
    }
}

