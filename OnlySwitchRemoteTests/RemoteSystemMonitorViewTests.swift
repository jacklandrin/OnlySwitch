import SwiftUI
import Testing
@testable import OnlySwitchRemote
import RemoteCore

@MainActor
struct RemoteSystemMonitorViewTests {
    @Test func iPhoneUsesAList() {
        #expect(
            RemoteSystemMonitorView.layout(
                for: .phone,
                containerSize: CGSize(width: 430, height: 932),
                dynamicTypeSize: .large
            ) == .list
        )
    }

    @Test func iPadMiniUsesTwoWaterfallColumns() {
        #expect(RemoteSystemMonitorWaterfallLayout.columnCount(
            containerWidth: 744,
            deviceClass: .iPadMini,
            dynamicTypeSize: .large
        ) == 2)
        #expect(
            RemoteSystemMonitorView.layout(
                for: .pad,
                containerSize: CGSize(width: 744, height: 1_133),
                dynamicTypeSize: .large
            ) == .waterfall(columns: 2)
        )
    }

    @Test func largerIPadUsesThreeWaterfallColumnsWhenTheContainerFits() {
        #expect(RemoteSystemMonitorWaterfallLayout.columnCount(
            containerWidth: 1_024,
            deviceClass: .iPad,
            dynamicTypeSize: .large
        ) == 3)
        #expect(
            RemoteSystemMonitorView.layout(
                for: .pad,
                containerSize: CGSize(width: 1_024, height: 1_366),
                dynamicTypeSize: .large
            ) == .waterfall(columns: 3)
        )
    }

    @Test func splitIPadDoesNotOvercommitToThreeWaterfallColumns() {
        #expect(RemoteSystemMonitorWaterfallLayout.columnCount(
            containerWidth: 560,
            deviceClass: .iPad,
            dynamicTypeSize: .large
        ) == 2)
        #expect(
            RemoteSystemMonitorView.layout(
                for: .pad,
                containerSize: CGSize(width: 560, height: 1_366),
                dynamicTypeSize: .large
            ) == .waterfall(columns: 2)
        )
    }

    @Test func accessibilityDynamicTypeCollapsesIPadWaterfallToAList() {
        #expect(RemoteSystemMonitorWaterfallLayout.columnCount(
            containerWidth: 1_024,
            deviceClass: .iPad,
            dynamicTypeSize: .accessibility3
        ) == 1)
        #expect(
            RemoteSystemMonitorView.layout(
                for: .pad,
                containerSize: CGSize(width: 1_024, height: 1_366),
                dynamicTypeSize: .accessibility3
            ) == .list
        )
    }

    @Test func waterfallPlacementRetainsOrderedVisibleMetricOrder() {
        let monitorLayout = MacSystemMonitorLayout(
            macID: UUID(),
            visibleMetrics: [.memory, .cpu, .network],
            order: [.memory, .disk, .cpu, .network]
        )
        let orderedVisibleMetrics = monitorLayout.orderedVisibleMetrics
        #expect(orderedVisibleMetrics == [.memory, .cpu, .network])
        let placements = RemoteSystemMonitorWaterfallLayout.placements(
            metrics: orderedVisibleMetrics,
            sizes: [
                CGSize(width: 220, height: 180),
                CGSize(width: 220, height: 148),
                CGSize(width: 220, height: 260),
            ],
            columnCount: 2,
            columnWidth: 220
        )

        #expect(placements.map(\.metric) == orderedVisibleMetrics)
        #expect(placements.map(\.column) == [0, 1, 1])
        #expect(placements[2].origin.y == 164)
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
