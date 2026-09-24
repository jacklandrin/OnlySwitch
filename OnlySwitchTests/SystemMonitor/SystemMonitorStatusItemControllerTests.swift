import Foundation
import SystemMonitor
import Testing
@testable import OnlySwitch

@MainActor
struct SystemMonitorStatusItemControllerTests {
    @Test
    func enablingCPUAndNetworkCreatesOnlyThoseIndicatorsInStableOrder() {
        let factory = RecordingSystemMonitorStatusItemFactory()
        let controller = SystemMonitorStatusItemController(
            factory: factory,
            client: .finished
        )

        controller.apply(.init(menuBarMetrics: [.network, .cpu]))

        #expect(factory.createdMetrics == [.cpu, .network])
        #expect(factory.items[.cpu]?.presentation?.title == "—")
        #expect(factory.items[.network]?.presentation?.title == "↓ —  ↑ —")
    }

    @Test
    func applyingNewPreferencesRemovesDeselectedItemsAndKeepsExistingItems() {
        let factory = RecordingSystemMonitorStatusItemFactory()
        let controller = SystemMonitorStatusItemController(
            factory: factory,
            client: .finished
        )
        controller.apply(.init(menuBarMetrics: [.cpu, .network]))
        let originalNetworkItem = factory.items[.network]

        controller.apply(.init(menuBarMetrics: [.memory, .network]))

        #expect(factory.createdMetrics == [.cpu, .network, .memory])
        #expect(factory.items[.cpu]?.removeCount == 1)
        #expect(factory.items[.network] === originalNetworkItem)
        #expect(factory.items[.network]?.removeCount == 0)
    }

    @Test
    func snapshotUpdatesEveryEnabledMetricPresentation() {
        let factory = RecordingSystemMonitorStatusItemFactory()
        let controller = SystemMonitorStatusItemController(
            factory: factory,
            client: .finished
        )
        controller.apply(.init(menuBarMetrics: Set(SystemMonitorMetric.allCases)))

        controller.receive(
            SystemMonitorSnapshot(
                timestamp: Date(timeIntervalSince1970: 1),
                cpuUsage: .available(0.42),
                gpuUsage: .available(0.25),
                memory: .available(.init(totalBytes: 16 * 1_024 * 1_024 * 1_024, usedBytes: 8 * 1_024 * 1_024 * 1_024)),
                disks: [.init(id: "disk", name: "Macintosh HD", totalBytes: 100, usedBytes: 75)],
                network: .available(.init(
                    totalDownloadedBytes: 0,
                    totalUploadedBytes: 0,
                    downloadBytesPerSecond: 1_536,
                    uploadBytesPerSecond: 2_048
                ))
            )
        )

        #expect(factory.items[.cpu]?.presentation?.title == "42%")
        #expect(factory.items[.gpu]?.presentation?.title == "25%")
        #expect(factory.items[.memory]?.presentation?.title == "8 GB")
        #expect(factory.items[.disk]?.presentation?.title == "75%")
        #expect(factory.items[.network]?.presentation?.title == "↓ 1.5 KB/s  ↑ 2 KB/s")
    }

    @Test
    func clickingAnIndicatorInvokesTheSharedPopoverAction() {
        let factory = RecordingSystemMonitorStatusItemFactory()
        var clickCount = 0
        let controller = SystemMonitorStatusItemController(
            factory: factory,
            client: .finished,
            onClick: { clickCount += 1 }
        )
        controller.apply(.init(menuBarMetrics: [.cpu]))

        factory.items[.cpu]?.click()

        #expect(clickCount == 1)
    }

    @Test
    func deinitializingControllerRemovesAllCreatedItems() {
        let factory = RecordingSystemMonitorStatusItemFactory()
        var controller: SystemMonitorStatusItemController? = SystemMonitorStatusItemController(
            factory: factory,
            client: .finished
        )
        controller?.apply(.init(menuBarMetrics: [.cpu, .disk]))

        controller = nil

        #expect(factory.items[.cpu]?.removeCount == 1)
        #expect(factory.items[.disk]?.removeCount == 1)
    }
}

@MainActor
private final class RecordingSystemMonitorStatusItemFactory: SystemMonitorStatusItemFactory {
    private(set) var createdMetrics: [SystemMonitorMetric] = []
    private(set) var items: [SystemMonitorMetric: RecordingSystemMonitorStatusItem] = [:]

    func makeStatusItem(for metric: SystemMonitorMetric) -> any SystemMonitorStatusItemHandle {
        createdMetrics.append(metric)
        let item = RecordingSystemMonitorStatusItem()
        items[metric] = item
        return item
    }
}

@MainActor
private final class RecordingSystemMonitorStatusItem: SystemMonitorStatusItemHandle {
    private(set) var presentation: SystemMonitorStatusItemPresentation?
    private(set) var removeCount = 0
    private var action: (@MainActor () -> Void)?

    func update(_ presentation: SystemMonitorStatusItemPresentation) {
        self.presentation = presentation
    }

    func setAction(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func remove() {
        removeCount += 1
    }

    func click() {
        action?()
    }
}

private extension SystemMonitorClient {
    static let finished = Self {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
