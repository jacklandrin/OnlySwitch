import Foundation
import SwiftUI
import RemoteCore

enum RemoteCodexUsageLayout {
    static func columnCount(availableWidth: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?) -> Int {
        horizontalSizeClass == .regular && availableWidth >= 700 ? 2 : 1
    }
}

enum RemoteCodexUsagePresentation {
    static let tabSymbol = "gauge.with.dots.needle.50percent"

    static func percentage(_ quota: CodexQuotaWindowDTO?) -> String {
        quota.map { "\($0.remainingPercent)%" } ?? String(localized: "Unavailable")
    }
    static func credits(_ value: CodexCreditBalanceDTO) -> String {
        switch value {
        case .unavailable:
            return String(localized: "Unavailable")
        case .unlimited:
            return String(localized: "Unlimited")
        case let .available(remaining, limit, unit):
            let format = FloatingPointFormatStyle<Double>.number
                .grouping(.automatic)
                .precision(.fractionLength(2))
            let remainingText = remaining.formatted(format)
            return limit.map { "\(remainingText) / \($0.formatted(format)) \(unit)" }
                ?? "\(remainingText) \(unit)"
        }
    }
}
