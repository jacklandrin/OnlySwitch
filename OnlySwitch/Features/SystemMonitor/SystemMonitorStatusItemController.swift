import AppKit
import Extensions
import SystemMonitor

struct SystemMonitorStatusItemPresentation: Equatable {
    let symbolName: String
    let title: String
    let accessibilityLabel: String
    let visualStyle: VisualStyle

    enum VisualStyle: Equatable {
        case standard
        case network
    }
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
                accessibilityLabel: "CPU %@".localizeWithFormat(arguments: value),
                visualStyle: .standard
            )

        case .gpu:
            let value = snapshot?.gpuUsage.value.map(SystemMonitorFormatter.percentage) ?? "—"
            return .init(
                symbolName: "rectangle.3.group",
                title: value,
                accessibilityLabel: "GPU %@".localizeWithFormat(arguments: value),
                visualStyle: .standard
            )

        case .memory:
            let value = snapshot?.memory.value.map {
                SystemMonitorFormatter.bytes(bytes: Double($0.usedBytes))
            } ?? "—"
            return .init(
                symbolName: "memorychip",
                title: value,
                accessibilityLabel: "Memory %@ used".localizeWithFormat(arguments: value),
                visualStyle: .standard
            )

        case .disk:
            let value = snapshot?.disks.first.map {
                SystemMonitorFormatter.percentage($0.usage)
            } ?? "—"
            return .init(
                symbolName: "internaldrive",
                title: value,
                accessibilityLabel: "Disk %@ used".localizeWithFormat(arguments: value),
                visualStyle: .standard
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
                title: "↓ \(download)\n↑ \(upload)",
                accessibilityLabel: "Network download %@, upload %@".localizeWithFormat(
                    arguments: download,
                    upload
                ),
                visualStyle: .network
            )
        }
    }
}

@MainActor
private final class AppKitSystemMonitorStatusItemFactory: SystemMonitorStatusItemFactory {
    func makeStatusItem(for metric: SystemMonitorMetric) -> any SystemMonitorStatusItemHandle {
        AppKitSystemMonitorStatusItem(metric: metric)
    }
}

@MainActor
private final class AppKitSystemMonitorStatusItem: SystemMonitorStatusItemHandle {
    private let item: NSStatusItem
    private let actionTarget = ActionTarget()
    private var isRemoved = false

    init(metric: SystemMonitorMetric, statusBar: NSStatusBar = .system) {
        item = statusBar.statusItem(withLength: Self.width(for: metric))
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
        switch presentation.visualStyle {
        case .standard:
            let image = NSImage(systemSymbolName: presentation.symbolName, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: presentation.title,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
            )

        case .network:
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = Self.networkTitle(presentation.title)
        }
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

    private static func width(for metric: SystemMonitorMetric) -> CGFloat {
        switch metric {
        case .cpu, .gpu, .disk:
            52
        case .memory:
            72
        case .network:
            64
        }
    }

    private static func networkTitle(_ title: String) -> NSAttributedString {
        let lines = title.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let download = lines.indices.contains(0) ? String(lines[0].dropFirst(2)) : "—"
        let upload = lines.indices.contains(1) ? String(lines[1].dropFirst(2)) : "—"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 9
        paragraphStyle.maximumLineHeight = 9
        paragraphStyle.alignment = .left
        let result = NSMutableAttributedString()
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        var markerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: NSColor.systemBlue,
            .paragraphStyle: paragraphStyle
        ]
        result.append(NSAttributedString(string: "● ", attributes: markerAttributes))
        result.append(NSAttributedString(string: "\(download)\n", attributes: valueAttributes))
        markerAttributes[.foregroundColor] = NSColor.systemRed
        result.append(NSAttributedString(string: "● ", attributes: markerAttributes))
        result.append(NSAttributedString(string: upload, attributes: valueAttributes))
        return result
    }

    @MainActor
    private final class ActionTarget: NSObject {
        var action: (@MainActor () -> Void)?

        @objc func performAction() {
            action?()
        }
    }
}
