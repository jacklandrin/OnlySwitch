import Aphrodite
import Foundation
import Testing
import Utilities

struct AdaptivePanelHeightPolicyTests {
    @Test func addsChromeToNaturalContentHeight() {
        let policy = AdaptivePanelHeightPolicy(
            minimumContentHeight: 120,
            chromeHeight: 40,
            maximumPanelHeight: 500
        )

        #expect(policy.panelHeight(for: 180) == 220)
    }

    @Test func usesMinimumForMissingOrInvalidMeasurements() {
        let policy = AdaptivePanelHeightPolicy(
            minimumContentHeight: 120,
            chromeHeight: 40,
            maximumPanelHeight: 500
        )

        #expect(policy.panelHeight(for: nil) == 160)
        #expect(policy.panelHeight(for: -1) == 160)
        #expect(policy.panelHeight(for: .infinity) == 160)
    }

    @Test func capsTheEntirePanelIncludingChrome() {
        let policy = AdaptivePanelHeightPolicy(
            minimumContentHeight: 120,
            chromeHeight: 40,
            maximumPanelHeight: 300
        )

        #expect(policy.panelHeight(for: 1_000) == 300)
        #expect(policy.panelHeight(for: 280) == 300)
    }
}

struct PopoverContentCapTests {
    @Test func subtractsNativePopoverChromeFromVisibleScreenHeight() {
        #expect(AdaptivePanelHeightPolicy.availableContentHeight(
            screenHeight: 1_050,
            windowHeight: 126,
            contentLayoutHeight: 100
        ) == 1_024)
    }

    @Test func borderlessHostKeepsItsFullVisibleHeight() {
        #expect(AdaptivePanelHeightPolicy.availableContentHeight(
            screenHeight: 1_050,
            windowHeight: 600,
            contentLayoutHeight: 600
        ) == 1_050)
    }

    @Test func invalidGeometryNeverProducesANegativeOrNonFiniteCap() {
        #expect(AdaptivePanelHeightPolicy.availableContentHeight(
            screenHeight: -10,
            windowHeight: 126,
            contentLayoutHeight: 100
        ) == 0)
        #expect(AdaptivePanelHeightPolicy.availableContentHeight(
            screenHeight: .infinity,
            windowHeight: 126,
            contentLayoutHeight: 100
        ) == 0)
        #expect(AdaptivePanelHeightPolicy.availableContentHeight(
            screenHeight: 100,
            windowHeight: -1,
            contentLayoutHeight: 100
        ) == 100)
    }
}

@MainActor
struct AphroditeContentHeightReportTests {
    @Test func acceptsAHeightForTheCurrentNavigation() {
        let token = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C111")!

        #expect(AphroditeContentHeightReport.parse(
            message: ["token": token.uuidString, "height": 240.5],
            expectedNavigationToken: token,
            maximumHeight: 20_000
        ) == 240.5)
    }

    @Test func rejectsStaleOrUnsafeReports() {
        let current = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C112")!
        let stale = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C113")!

        #expect(AphroditeContentHeightReport.parse(
            message: ["token": stale.uuidString, "height": 240],
            expectedNavigationToken: current,
            maximumHeight: 20_000
        ) == nil)
        #expect(AphroditeContentHeightReport.parse(
            message: ["token": current.uuidString, "height": Double.infinity],
            expectedNavigationToken: current,
            maximumHeight: 20_000
        ) == nil)
        #expect(AphroditeContentHeightReport.parse(
            message: ["token": current.uuidString, "height": 20_001],
            expectedNavigationToken: current,
            maximumHeight: 20_000
        ) == nil)
    }

    @Test func suppressesJitterButReportsGrowthAndShrink() {
        #expect(!AphroditeContentHeightReport.shouldReport(previous: 240, next: 240.5))
        #expect(AphroditeContentHeightReport.shouldReport(previous: 240, next: 400))
        #expect(AphroditeContentHeightReport.shouldReport(previous: 400, next: 180))
    }
}
