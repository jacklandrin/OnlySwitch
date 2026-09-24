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
        #expect(factory.items[.network]?.presentation?.title == "↑ —\n↓ —")
        #expect(factory.items[.network]?.presentation?.visualStyle == .network)
    }

    @Test
    func incrementalPreferenceChangesRebuildTheSameCanonicalOrderAsColdLaunch() {
        let incrementalFactory = RecordingSystemMonitorStatusItemFactory()
        let controller = SystemMonitorStatusItemController(
            factory: incrementalFactory,
            client: .finished
        )
        controller.apply(.init(menuBarMetrics: [.cpu, .network]))
        let originalCPUItem = incrementalFactory.items[.cpu]
        let originalNetworkItem = incrementalFactory.items[.network]

        controller.apply(.init(menuBarMetrics: [.memory, .network]))

        let coldFactory = RecordingSystemMonitorStatusItemFactory()
        let coldController = SystemMonitorStatusItemController(
            factory: coldFactory,
            client: .finished
        )
        coldController.apply(.init(menuBarMetrics: [.memory, .network]))

        #expect(originalCPUItem?.removeCount == 1)
        #expect(originalNetworkItem?.removeCount == 1)
        #expect(Array(incrementalFactory.createdMetrics.suffix(2)) == coldFactory.createdMetrics)
        #expect(coldFactory.createdMetrics == [.memory, .network])
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
        #expect(factory.items[.network]?.presentation?.title == "↑ 2 KB/s\n↓ 2 KB/s")
    }

    @Test
    func menuBarValuesUseWholeNumbersWithoutChangingThePanelFormatter() {
        let factory = RecordingSystemMonitorStatusItemFactory()
        let controller = SystemMonitorStatusItemController(
            factory: factory,
            client: .finished
        )
        controller.apply(.init(menuBarMetrics: Set(SystemMonitorMetric.allCases)))

        controller.receive(
            SystemMonitorSnapshot(
                timestamp: Date(timeIntervalSince1970: 1),
                cpuUsage: .available(0.179),
                gpuUsage: .available(0.006),
                memory: .available(.init(totalBytes: 10_000, usedBytes: 1_536)),
                disks: [.init(id: "disk", name: "Macintosh HD", totalBytes: 100, usedBytes: 666)],
                network: .available(.init(
                    totalDownloadedBytes: 0,
                    totalUploadedBytes: 0,
                    downloadBytesPerSecond: 1_536,
                    uploadBytesPerSecond: 4_710
                ))
            )
        )

        #expect(factory.items[.cpu]?.presentation?.title == "18%")
        #expect(factory.items[.gpu]?.presentation?.title == "1%")
        #expect(factory.items[.memory]?.presentation?.title == "2 KB")
        #expect(factory.items[.disk]?.presentation?.title == "100%")
        #expect(factory.items[.network]?.presentation?.title == "↑ 5 KB/s\n↓ 2 KB/s")
        #expect(SystemMonitorFormatter.rate(bytesPerSecond: 1_536) == "1.5 KB/s")
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

    @Test
    func metricChangesKeepOneUpstreamAndDisablingTheLastItemCancelsIt() async {
        let factory = RecordingSystemMonitorStatusItemFactory()
        let clients = RecordingMonitorClientFactory()
        let controller = SystemMonitorStatusItemController(
            factory: factory,
            clientFactory: clients.makeClient(refreshInterval:)
        )

        controller.apply(.init(menuBarMetrics: [.cpu]))
        await Task.yield()
        controller.apply(.init(menuBarMetrics: [.cpu, .network]))
        await Task.yield()

        #expect(clients.streamStartCount == 1)

        controller.apply(.init(menuBarMetrics: []))
        for _ in 0..<10 where clients.terminationCount == 0 {
            await Task.yield()
        }

        #expect(clients.terminationCount == 1)
    }

    @Test
    func changingRefreshIntervalRestartsTheUpstreamWithTheNewInterval() async {
        let factory = RecordingSystemMonitorStatusItemFactory()
        let clients = RecordingMonitorClientFactory()
        let controller = SystemMonitorStatusItemController(
            factory: factory,
            clientFactory: clients.makeClient(refreshInterval:)
        )

        controller.apply(.init(menuBarMetrics: [.cpu], refreshInterval: 1))
        await Task.yield()
        controller.apply(.init(menuBarMetrics: [.cpu], refreshInterval: 2))
        for _ in 0..<10 where clients.streamStartCount < 2 {
            await Task.yield()
        }

        #expect(clients.requestedIntervals == [1, 2])
        #expect(clients.streamStartCount == 2)
        #expect(clients.terminationCount == 1)
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

private final class RecordingMonitorClientFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var intervals: [TimeInterval] = []
    private var starts = 0
    private var terminations = 0

    var requestedIntervals: [TimeInterval] {
        lock.withLock { intervals }
    }

    var streamStartCount: Int {
        lock.withLock { starts }
    }

    var terminationCount: Int {
        lock.withLock { terminations }
    }

    func makeClient(refreshInterval: TimeInterval) -> SystemMonitorClient {
        lock.withLock { intervals.append(refreshInterval) }
        return SystemMonitorClient { [weak self] in
            guard let self else {
                return AsyncThrowingStream { $0.finish() }
            }
            self.lock.withLock { self.starts += 1 }
            return AsyncThrowingStream { continuation in
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    self.lock.withLock { self.terminations += 1 }
                }
            }
        }
    }
}
