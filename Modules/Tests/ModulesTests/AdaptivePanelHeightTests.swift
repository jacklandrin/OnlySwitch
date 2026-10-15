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

struct AphroditeEditorPreviewScalePolicyTests {
    @Test func fitsWideAndTallContentWithoutChangingItsLogicalCanvas() throws {
        let layout = try #require(AphroditeEditorPreviewScalePolicy.layout(
            content: .init(width: 1_048, height: 900),
            available: .init(width: 340, height: 500)
        ))

        #expect(layout.scale == CGFloat(340) / 1_048)
        #expect(layout.displayedSize.width == 340)
        #expect(layout.displayedSize.height <= 500)
        #expect(layout.logicalSize == .init(width: 1_048, height: 900))
    }

    @Test func doesNotUpscaleSmallContent() throws {
        let layout = try #require(AphroditeEditorPreviewScalePolicy.layout(
            content: .init(width: 200, height: 100),
            available: .init(width: 900, height: 700)
        ))

        #expect(layout.scale == 1)
        #expect(layout.logicalSize == .init(width: 640, height: 100))
        #expect(layout.displayedSize == .init(width: 640, height: 100))
    }

    @Test func rejectsInvalidGeometry() {
        #expect(AphroditeEditorPreviewScalePolicy.layout(
            content: .init(width: CGFloat.infinity, height: 100), available: .init(width: 300, height: 300)
        ) == nil)
        #expect(AphroditeEditorPreviewScalePolicy.layout(
            content: .init(width: 300, height: 0), available: .init(width: 300, height: 300)
        ) == nil)
        #expect(AphroditeEditorPreviewScalePolicy.layout(
            content: .init(width: 300, height: 100), available: .init(width: CGFloat.nan, height: 300)
        ) == nil)
    }

    @Test func heightConstraintCanDetermineTheFitScale() throws {
        let layout = try #require(AphroditeEditorPreviewScalePolicy.layout(
            content: .init(width: 640, height: 1_200), available: .init(width: 900, height: 300)
        ))

        #expect(layout.scale == 0.25)
        #expect(layout.displayedSize == .init(width: 160, height: 300))
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

@MainActor
struct AphroditeContentSizeReportTests {
    @Test func acceptsTheCurrentBoundedContentSize() {
        let token = UUID()
        #expect(AphroditeContentSizeReport.parse(
            message: ["token": token.uuidString, "width": 640, "height": 480],
            expectedNavigationToken: token,
            maximumDimension: 20_000
        ) == .init(width: 640, height: 480))
    }

    @Test func rejectsStaleAndUnsafeDimensions() {
        let current = UUID()
        let stale = UUID()
        let invalid: [[String: Any]] = [
            ["token": stale.uuidString, "width": 640, "height": 480],
            ["token": current.uuidString, "width": Double.nan, "height": 480],
            ["token": current.uuidString, "width": 640, "height": Double.infinity],
            ["token": current.uuidString, "width": 0, "height": 480],
            ["token": current.uuidString, "width": 640, "height": 20_001]
        ]

        for message in invalid {
            #expect(AphroditeContentSizeReport.parse(
                message: message, expectedNavigationToken: current, maximumDimension: 20_000
            ) == nil)
        }
    }

    @Test func suppressesSubPointJitterButReportsAWidthChange() {
        let previous = CGSize(width: 640, height: 480)
        #expect(!AphroditeContentSizeReport.shouldReport(previous: previous, next: .init(width: 640.5, height: 480)))
        #expect(AphroditeContentSizeReport.shouldReport(previous: previous, next: .init(width: 700, height: 480)))
    }
}
