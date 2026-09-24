import Foundation
import SystemMonitor
import Testing
@testable import OnlySwitch

struct SystemMonitorLocalizationTests {
    @Test(arguments: [
        (SystemMonitorMetric.cpu, "CPU"),
        (.gpu, "GPU"),
        (.memory, "Memory"),
        (.disk, "Disk"),
        (.network, "Network")
    ])
    func metricDisplayTitleKeysUseCanonicalLocalizableCatalogKeys(
        metric: SystemMonitorMetric,
        expectedKey: String
    ) {
        #expect(metric.displayTitleKey == expectedKey)
        #expect(metric.displayTitleKey.localized().isEmpty == false)
    }

    @Test
    @MainActor
    func networkIndicatorAccessibilityDescribesDownloadBeforeUpload() {
        let snapshot = SystemMonitorSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            network: .available(.init(
                totalDownloadedBytes: 0,
                totalUploadedBytes: 0,
                downloadBytesPerSecond: 1_536,
                uploadBytesPerSecond: 2_048
            ))
        )

        let presentation = SystemMonitorStatusItemController.presentation(
            for: .network,
            snapshot: snapshot
        )

        #expect(presentation.accessibilityLabel == "Network download 2 KB/s, upload 2 KB/s")
    }
}
