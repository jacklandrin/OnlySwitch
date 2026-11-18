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
    private let clientFactory: @Sendable (TimeInterval, Set<SystemMonitorMetric>) -> SystemMonitorClient
    private let onClick: @MainActor () -> Void
    private var items: [SystemMonitorMetric: any SystemMonitorStatusItemHandle] = [:]
    private var enabledMetrics: Set<SystemMonitorMetric> = []
    private var refreshInterval: TimeInterval?
    private var latestSnapshot: SystemMonitorSnapshot?
    private var samplingTask: Task<Void, Never>?
    private var samplingGeneration = 0

    init(
        factory: any SystemMonitorStatusItemFactory = AppKitSystemMonitorStatusItemFactory(),
        clientFactory: @escaping @Sendable (TimeInterval, Set<SystemMonitorMetric>) -> SystemMonitorClient = {
            MacSystemMonitorCollector.liveClient(
                refreshInterval: $0,
                metrics: $1,
                includeDetails: false
            )
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
        self.init(factory: factory, clientFactory: { _, _ in client }, onClick: onClick)
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
            if metricsChanged || intervalChanged {
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
        let client = clientFactory(refreshInterval, enabledMetrics)

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
            let value = snapshot?.cpuUsage.value.map(SystemMonitorStatusItemFormatter.percentage) ?? "—"
            return .init(
                symbolName: "cpu",
                title: value,
                accessibilityLabel: "CPU %@".localizeWithFormat(arguments: value),
                visualStyle: .standard
            )

        case .gpu:
            let value = snapshot?.gpuUsage.value.map(SystemMonitorStatusItemFormatter.percentage) ?? "—"
            return .init(
                symbolName: "rectangle.3.group",
                title: value,
                accessibilityLabel: "GPU %@".localizeWithFormat(arguments: value),
                visualStyle: .standard
            )

        case .memory:
            let value = snapshot?.memory.value.map {
                guard $0.totalBytes > 0 else { return "—" }
                return SystemMonitorStatusItemFormatter.percentage(
                    Double($0.usedBytes) / Double($0.totalBytes)
                )
            } ?? "—"
            return .init(
                symbolName: "memorychip",
                title: value,
                accessibilityLabel: "Memory %@ used".localizeWithFormat(arguments: value),
                visualStyle: .standard
            )

        case .disk:
            let value = snapshot?.disks.first.map {
                SystemMonitorStatusItemFormatter.percentage($0.usage)
            } ?? "—"
            return .init(
                symbolName: "internaldrive",
                title: value,
                accessibilityLabel: "Disk %@ used".localizeWithFormat(arguments: value),
                visualStyle: .standard
            )

        case .network:
            let download = snapshot?.network.value.map {
                SystemMonitorStatusItemFormatter.rate(bytesPerSecond: $0.downloadBytesPerSecond)
            } ?? "—"
            let upload = snapshot?.network.value.map {
                SystemMonitorStatusItemFormatter.rate(bytesPerSecond: $0.uploadBytesPerSecond)
            } ?? "—"
            return .init(
                symbolName: "network",
                title: "↑ \(upload)\n↓ \(download)",
                accessibilityLabel: "Network download %@, upload %@".localizeWithFormat(
                    arguments: download,
                    upload
                ),
                visualStyle: .network
            )
        }
    }
}

/// Compact, whole-number values for fixed-width menu-bar indicators.
///
/// The richer monitor panel deliberately continues to use `SystemMonitorFormatter`,
/// which retains its existing precision.
private enum SystemMonitorStatusItemFormatter {
    static func rate(bytesPerSecond: Double) -> String {
        "\(bytes(bytes: bytesPerSecond))/s"
    }

    static func bytes(bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(bytes, 0)
        var unitIndex = 0

        while value >= 1_024, unitIndex < units.count - 1 {
            value /= 1_024
            unitIndex += 1
        }

        let roundedValue = value.rounded()
        return "\(Int(roundedValue)) \(units[unitIndex])"
    }

    static func percentage(_ value: Double) -> String {
        let percentage = min(max(value, 0), 1) * 100
        return "\(Int(percentage.rounded()))%"
    }
}

private enum SystemMonitorStatusItemImage {
    static func make(
        for presentation: SystemMonitorStatusItemPresentation,
        size: NSSize
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            switch presentation.visualStyle {
            case .standard:
                drawStandard(presentation, in: bounds)
            case .network:
                drawNetwork(presentation, in: bounds)
            }
            return true
        }
        image.isTemplate = presentation.visualStyle == .standard
        if presentation.visualStyle == .network {
            // Resolve the label and dot colors in the current menu bar appearance.
            image.cacheMode = .never
        }
        return image
    }

    private static func drawStandard(
        _ presentation: SystemMonitorStatusItemPresentation,
        in bounds: NSRect
    ) {
        let iconSide: CGFloat = 16
        if let icon = NSImage(systemSymbolName: presentation.symbolName, accessibilityDescription: nil),
           icon.size.width > 0, icon.size.height > 0 {
            let scale = min(1, iconSide / max(icon.size.width, icon.size.height))
            let width = icon.size.width * scale
            let height = icon.size.height * scale
            icon.draw(in: NSRect(
                x: bounds.minX + 5 + (iconSide - width) / 2,
                y: bounds.midY - height / 2,
                width: width,
                height: height
            ))
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        drawValue(
            presentation.title,
            font: font,
            color: .black,
            in: NSRect(
                x: bounds.minX + 24,
                y: bounds.minY,
                width: bounds.width - 28,
                height: bounds.height
            )
        )
    }

    private static func drawNetwork(
        _ presentation: SystemMonitorStatusItemPresentation,
        in bounds: NSRect
    ) {
        let lines = presentation.title.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let upload = lines.first.map { String($0.dropFirst(2)) } ?? "—"
        let download = lines.dropFirst().first.map { String($0.dropFirst(2)) } ?? "—"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let lineHeight: CGFloat = 10
        let rows: [(value: String, color: NSColor, y: CGFloat)] = [
            (upload, .systemRed, bounds.midY),
            (download, .systemBlue, bounds.midY - lineHeight),
        ]

        for row in rows {
            row.color.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: bounds.minX + 7,
                y: row.y + (lineHeight - 7) / 2,
                width: 7,
                height: 7
            )).fill()
            drawValue(
                row.value,
                font: font,
                color: .labelColor,
                in: NSRect(
                    x: bounds.minX + 21,
                    y: row.y,
                    width: bounds.width - 26,
                    height: lineHeight
                )
            )
        }
    }

    private static func drawValue(_ value: String, font: NSFont, color: NSColor, in bounds: NSRect) {
        let text = NSAttributedString(string: value, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let size = text.size()
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath.clip(bounds)
        text.draw(at: NSPoint(x: bounds.maxX - size.width, y: bounds.midY - size.height / 2))
    }
}

@MainActor
private final class AppKitSystemMonitorStatusItemFactory: SystemMonitorStatusItemFactory {
    func makeStatusItem(for metric: SystemMonitorMetric) -> any SystemMonitorStatusItemHandle {
        AppKitSystemMonitorStatusItem(metric: metric)
    }
}

@MainActor
final class AppKitSystemMonitorStatusItem: SystemMonitorStatusItemHandle {
    private let item: NSStatusItem
    private let actionTarget = ActionTarget()
    private var isRemoved = false

    convenience init(metric: SystemMonitorMetric) {
        let item = NSStatusBar.system.statusItem(withLength: Self.width(for: metric))
        self.init(metric: metric, item: item)
    }

    init(metric: SystemMonitorMetric, item: NSStatusItem) {
        self.item = item
        item.length = Self.width(for: metric)
        StatusBarController.configureStatusItem(item)

        guard let button = item.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.sendAction(on: [.leftMouseUp])
        button.target = actionTarget
        button.action = #selector(ActionTarget.performAction)
    }

    func update(_ presentation: SystemMonitorStatusItemPresentation) {
        guard let button = item.button else { return }
        // Let AppKit host the indicator image without laying out custom button subviews.
        button.image = SystemMonitorStatusItemImage.make(
            for: presentation,
            size: NSSize(width: item.length, height: NSStatusBar.system.thickness)
        )
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
        case .cpu, .gpu, .memory, .disk:
            64
        case .network:
            80
        }
    }

    @MainActor
    private final class ActionTarget: NSObject {
        var action: (@MainActor () -> Void)?

        @objc func performAction() {
            action?()
        }
    }
}
