import SwiftUI
import Testing
import RemoteCore
@testable import OnlySwitchRemote

struct RemoteCodexUsageViewTests {
    @Test func tabUsesTheSameUsageGaugeSymbolAsOnlySwitch() {
        #expect(RemoteCodexUsagePresentation.tabSymbol == "gauge.with.dots.needle.50percent")
    }

    @Test func compactIPhoneAlwaysUsesOneColumn() {
        #expect(RemoteCodexUsageLayout.columnCount(
            availableWidth: 430,
            horizontalSizeClass: .compact
        ) == 1)
    }

    @Test func fullWidthIPadUsesTwoColumns() {
        #expect(RemoteCodexUsageLayout.columnCount(
            availableWidth: 1_024,
            horizontalSizeClass: .regular
        ) == 2)
    }

    @Test func narrowIPadSplitViewFallsBackToOneColumn() {
        #expect(RemoteCodexUsageLayout.columnCount(
            availableWidth: 560,
            horizontalSizeClass: .regular
        ) == 1)
    }

    @Test func creditsAlwaysUseTwoFractionDigits() {
        let displayed = RemoteCodexUsagePresentation.credits(
            .available(remaining: 2_170.840555, limit: nil, unit: "credits")
        )

        #expect(displayed.hasSuffix("credits"))
        #expect(displayed.contains(".84") || displayed.contains(",84"))
        #expect(displayed.contains("840555") == false)
    }
}
