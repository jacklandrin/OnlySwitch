import SwiftUI
import Testing
@testable import OnlySwitchRemote
import RemoteCore

@MainActor
struct RemoteSystemMonitorViewTests {
    @Test func phoneUsesAListAndStandardIPadUsesTwoColumns() {
        #expect(RemoteSystemMonitorView.layout(for: .phone, dynamicTypeSize: .large) == .list)
        #expect(RemoteSystemMonitorView.layout(for: .pad, dynamicTypeSize: .large) == .grid(columns: 2))
    }

    @Test func accessibilityDynamicTypeCollapsesIPadGridToAList() {
        #expect(RemoteSystemMonitorView.layout(for: .pad, dynamicTypeSize: .accessibility3) == .list)
    }

    @Test(arguments: [
        (rawUsage: -0.25, expectedUsage: 0.0, expectedAccessibilityValue: "0%"),
        (rawUsage: 0.84, expectedUsage: 0.84, expectedAccessibilityValue: "84%"),
        (rawUsage: 1.25, expectedUsage: 1.0, expectedAccessibilityValue: "100%")
    ])
    func gaugeClampsAvailableUsageToItsDisplayRange(
        rawUsage: Double,
        expectedUsage: Double,
        expectedAccessibilityValue: String
    ) {
        let gauge = RemoteSystemMonitorGaugePresentation(
            title: "CPU",
            usage: .available(rawUsage)
        )

        #expect(gauge.usage == expectedUsage)
        #expect(gauge.accessibilityLabel == "CPU usage")
        #expect(gauge.accessibilityValue == expectedAccessibilityValue)
    }

    @Test func unavailableGaugeHasNoUsageAndAnnouncesItsState() {
        let gauge = RemoteSystemMonitorGaugePresentation(
            title: "GPU",
            usage: .unavailable
        )

        #expect(gauge.usage == nil)
        #expect(gauge.accessibilityLabel == "GPU usage")
        #expect(gauge.accessibilityValue == "Unavailable")
    }

    @Test func compactTabBarKeepsAStandardHeightAndPointerSizedTouchTarget() {
        #expect(RemotePageTabBar.visualHeight == 44)
        #expect(RemotePageTabBar.minimumTouchHeight == 44)
        #expect(RemotePageTabBar.minimumTouchHeight >= 44)
    }

    @Test func monitorGaugeUsesDistinctMetricAccentsAndCenterValue() {
        #expect(RemoteSystemMonitorGaugeAccent(metric: .cpu) == .cpu)
        #expect(RemoteSystemMonitorGaugeAccent(metric: .gpu) == .gpu)
        #expect(RemoteSystemMonitorGaugeAccent(metric: .memory) == .memory)
        #expect(
            RemoteSystemMonitorGaugePresentation(title: "Memory", usage: .available(0.84)).displayValue == "84%"
        )
    }

    @Test func diskPresentationNeverIncludesTemperature() {
        let disk = SystemMonitorDisk(
            id: "root",
            name: "Macintosh HD",
            totalBytes: 1_000,
            usedBytes: 500,
            temperatureCelsius: .available(51)
        )

        let presentation = RemoteSystemMonitorView.diskPresentation(disk)

        #expect(presentation.name == "Macintosh HD")
        #expect(presentation.usage == 0.5)
        #expect(presentation.rows.map(\.title).contains("Temperature") == false)
    }

    @Test func monitorChromeKeepsTouchTargetsButBoundsVisualWidth() {
        #expect(RemotePageTabBar.visualHeight == 44)
        #expect(RemotePageTabBar.minimumTouchHeight == 44)
        #expect(RemotePageTabBar.contentBottomInset == RemotePageTabBar.minimumTouchHeight + 4)
        #expect(RemotePageTabBar.contentBottomInset == 48)
        #expect(RemotePageTabBar.maximumWidth == 260)
        #expect(RemoteSystemMonitorCardSurface.lightModeShadowOpacity == 0.12)
    }
}
