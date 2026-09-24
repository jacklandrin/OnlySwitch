import AppKit
import Extensions
import SystemMonitor

struct SystemMonitorStatusItemPresentation: Equatable {
    let symbolName: String
    let title: String
    let accessibilityLabel: String
}

@MainActor
protocol SystemMonitorStatusItemHandle: AnyObject {
    func update(_ presentation: SystemMonitorStatusItemPresentation)
    func setAction(_ action: @escaping @MainActor () -> Void)
    func remove()
}

@MainActor
protocol SystemMonitorStatusItemFactory: AnyObject {
    func makeStatusItem(for metric: SystemMonitorMetric) -> any SystemMonitorStatusItemHandle
}

@MainActor
final class SystemMonitorStatusItemController {
    private let factory: any SystemMonitorStatusItemFactory
    private let clientFactory: @Sendable (TimeInterval) -> SystemMonitorClient
    private let onClick: @MainActor () -> Void
    private var items: [SystemMonitorMetric: any SystemMonitorStatusItemHandle] = [:]
    private var enabledMetrics: Set<SystemMonitorMetric> = []
    private var refreshInterval: TimeInterval?
    private var latestSnapshot: SystemMonitorSnapshot?
    private var samplingTask: Task<Void, Never>?
    private var samplingGeneration = 0

    init(
        factory: any SystemMonitorStatusItemFactory = AppKitSystemMonitorStatusItemFactory(),
        clientFactory: @escaping @Sendable (TimeInterval) -> SystemMonitorClient = {
            MacSystemMonitorCollector.liveClient(refreshInterval: $0)
        },
        onClick: @escaping @MainActor () -> Void = {}
    ) {
        self.factory = factory
        self.clientFactory = clientFactory
        self.onClick = onClick
    }

    convenience init(
        factory: any SystemMonitorStatusItemFactory,
        client: SystemMonitorClient,
        onClick: @escaping @MainActor () -> Void = {}
    ) {
        self.init(factory: factory, clientFactory: { _ in client }, onClick: onClick)
    }

    func apply(_ preferences: SystemMonitorPreferences) {
        let selectedMetrics = preferences.menuBarMetrics
        let metricsChanged = selectedMetrics != enabledMetrics
        let intervalChanged = refreshInterval != preferences.refreshInterval
        enabledMetrics = selectedMetrics
        refreshInterval = preferences.refreshInterval

        if metricsChanged {
            rebuildItems(for: selectedMetrics)
        }

        if items.isEmpty {
            stopSampling()
        } else {
            if intervalChanged {
                stopSampling()
            }
            startSamplingIfNeeded()
        }
    }

    func receive(_ snapshot: SystemMonitorSnapshot) {
        latestSnapshot = snapshot
        for metric in SystemMonitorMetric.allCases {
            items[metric]?.update(Self.presentation(for: metric, snapshot: snapshot))
        }
    }

    isolated deinit {
        samplingTask?.cancel()
        for item in items.values {
            item.remove()
        }
    }
}

private extension SystemMonitorStatusItemController {
    func rebuildItems(for selectedMetrics: Set<SystemMonitorMetric>) {
        for item in items.values {
            item.remove()
        }
        items.removeAll(keepingCapacity: true)

        for metric in SystemMonitorMetric.allCases where selectedMetrics.contains(metric) {
            let item = factory.makeStatusItem(for: metric)
            item.setAction(onClick)
            item.update(Self.presentation(for: metric, snapshot: latestSnapshot))
            items[metric] = item
        }
    }

    func startSamplingIfNeeded() {
        guard samplingTask == nil else { return }
        guard let refreshInterval else { return }
        samplingGeneration += 1
        let generation = samplingGeneration
        let client = clientFactory(refreshInterval)

        samplingTask = Task { @MainActor [weak self] in
            do {
                for try await snapshot in client.snapshots() {
                    try Task.checkCancellation()
                    guard let self else { return }
                    self.receive(snapshot)
                }
            } catch is CancellationError {
                // Disabling the final indicator intentionally cancels this stream.
            } catch {
                // Keep the last good value visible. A future preference change can restart it.
            }
            self?.samplingDidFinish(generation: generation)
        }
    }

    func stopSampling() {
        samplingGeneration += 1
        samplingTask?.cancel()
        samplingTask = nil
    }

    func samplingDidFinish(generation: Int) {
        guard samplingGeneration == generation else { return }
        samplingTask = nil
    }

    static func presentation(
        for metric: SystemMonitorMetric,
        snapshot: SystemMonitorSnapshot?
    ) -> SystemMonitorStatusItemPresentation {
        switch metric {
        case .cpu:
            let value = snapshot?.cpuUsage.value.map(SystemMonitorFormatter.percentage) ?? "—"
            return .init(
                symbolName: "cpu",
                title: value,
                accessibilityLabel: "CPU %@".localizeWithFormat(arguments: value)
            )

        case .gpu:
            let value = snapshot?.gpuUsage.value.map(SystemMonitorFormatter.percentage) ?? "—"
            return .init(
                symbolName: "rectangle.3.group",
                title: value,
                accessibilityLabel: "GPU %@".localizeWithFormat(arguments: value)
            )

        case .memory:
            let value = snapshot?.memory.value.map {
                SystemMonitorFormatter.bytes(bytes: Double($0.usedBytes))
            } ?? "—"
            return .init(
                symbolName: "memorychip",
                title: value,
                accessibilityLabel: "Memory %@ used".localizeWithFormat(arguments: value)
            )

        case .disk:
            let value = snapshot?.disks.first.map {
                SystemMonitorFormatter.percentage($0.usage)
            } ?? "—"
            return .init(
                symbolName: "internaldrive",
                title: value,
                accessibilityLabel: "Disk %@ used".localizeWithFormat(arguments: value)
            )

        case .network:
            let download = snapshot?.network.value.map {
                SystemMonitorFormatter.rate(bytesPerSecond: $0.downloadBytesPerSecond)
            } ?? "—"
            let upload = snapshot?.network.value.map {
                SystemMonitorFormatter.rate(bytesPerSecond: $0.uploadBytesPerSecond)
            } ?? "—"
            return .init(
                symbolName: "network",
                title: "↓ \(download)  ↑ \(upload)",
                accessibilityLabel: "Network download %@, upload %@".localizeWithFormat(
                    arguments: download,
                    upload
                )
            )
        }
    }
}

@MainActor
private final class AppKitSystemMonitorStatusItemFactory: SystemMonitorStatusItemFactory {
    func makeStatusItem(for metric: SystemMonitorMetric) -> any SystemMonitorStatusItemHandle {
        AppKitSystemMonitorStatusItem()
    }
}

@MainActor
private final class AppKitSystemMonitorStatusItem: SystemMonitorStatusItemHandle {
    private let item: NSStatusItem
    private let actionTarget = ActionTarget()
    private var isRemoved = false

    init(statusBar: NSStatusBar = .system) {
        item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        StatusBarController.configureStatusItem(item)

        guard let button = item.button else { return }
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.sendAction(on: [.leftMouseUp])
        button.target = actionTarget
        button.action = #selector(ActionTarget.performAction)
    }

    func update(_ presentation: SystemMonitorStatusItemPresentation) {
        guard let button = item.button else { return }
        let image = NSImage(systemSymbolName: presentation.symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.title = presentation.title
        button.toolTip = presentation.accessibilityLabel
        button.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    func setAction(_ action: @escaping @MainActor () -> Void) {
        actionTarget.action = action
    }

    func remove() {
        guard !isRemoved else { return }
        isRemoved = true
        actionTarget.action = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    @MainActor
    private final class ActionTarget: NSObject {
        var action: (@MainActor () -> Void)?

        @objc func performAction() {
            action?()
        }
    }
}
