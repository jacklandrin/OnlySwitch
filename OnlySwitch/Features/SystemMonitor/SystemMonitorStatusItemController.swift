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
                accessibilityLabel: "Network upload %@, download %@".localizeWithFormat(
                    arguments: upload,
                    download
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

@MainActor
private final class StatusItemContentView: NSView {
    private let metric: SystemMonitorMetric
    private let imageView = NSImageView()
    private let valueLabel = NSTextField(labelWithString: "")
    private let topDot = NSTextField(labelWithString: "●")
    private let bottomDot = NSTextField(labelWithString: "●")
    private let topValueLabel = NSTextField(labelWithString: "")
    private let bottomValueLabel = NSTextField(labelWithString: "")

    init(metric: SystemMonitorMetric) {
        self.metric = metric
        super.init(frame: .zero)

        wantsLayer = false
        configureStandardContent()
        configureNetworkContent()
        let isNetwork = metric == .network
        imageView.isHidden = isNetwork
        valueLabel.isHidden = isNetwork
        topDot.isHidden = !isNetwork
        bottomDot.isHidden = !isNetwork
        topValueLabel.isHidden = !isNetwork
        bottomValueLabel.isHidden = !isNetwork
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard metric == .network else {
            let iconSide: CGFloat = 16
            let leading: CGFloat = 5
            let labelHeight = ceil(valueLabel.font?.boundingRectForFont.height ?? 13)
            imageView.frame = CGRect(
                x: leading,
                y: (bounds.height - iconSide) / 2,
                width: iconSide,
                height: iconSide
            )
            valueLabel.frame = CGRect(
                x: leading + iconSide + 3,
                y: floor((bounds.height - labelHeight) / 2),
                width: max(0, bounds.width - (leading + iconSide + 3) - 4),
                height: labelHeight
            )
            return
        }

        let lineHeight: CGFloat = 10
        let totalHeight = lineHeight * 2
        let topY = (bounds.height + totalHeight) / 2 - lineHeight
        let bottomY = topY - lineHeight
        // `NSTextField` can draw the dot glyph slightly outside its frame. Keep
        // a generous inset so status-bar clipping never cuts the circular mark.
        let dotLeading: CGFloat = 7
        let dotWidth: CGFloat = 11
        let valueLeading: CGFloat = 21
        let valueWidth = max(0, bounds.width - valueLeading - 5)

        topDot.frame = CGRect(x: dotLeading, y: topY, width: dotWidth, height: lineHeight)
        bottomDot.frame = CGRect(x: dotLeading, y: bottomY, width: dotWidth, height: lineHeight)
        topValueLabel.frame = CGRect(x: valueLeading, y: topY, width: valueWidth, height: lineHeight)
        bottomValueLabel.frame = CGRect(x: valueLeading, y: bottomY, width: valueWidth, height: lineHeight)
    }

    // The status-bar button remains the single click target; this view is visual only.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(_ presentation: SystemMonitorStatusItemPresentation) {
        switch presentation.visualStyle {
        case .standard:
            let image = NSImage(systemSymbolName: presentation.symbolName, accessibilityDescription: nil)
            image?.isTemplate = true
            imageView.image = image
            valueLabel.stringValue = presentation.title

        case .network:
            let lines = presentation.title.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            topValueLabel.stringValue = lines.indices.contains(0) ? String(lines[0].dropFirst(2)) : "—"
            bottomValueLabel.stringValue = lines.indices.contains(1) ? String(lines[1].dropFirst(2)) : "—"
        }
    }

    private func configureStandardContent() {
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byClipping
        addSubview(imageView)
        addSubview(valueLabel)
    }

    private func configureNetworkContent() {
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        for valueLabel in [topValueLabel, bottomValueLabel] {
            valueLabel.font = valueFont
            valueLabel.textColor = .labelColor
            valueLabel.alignment = .right
            valueLabel.lineBreakMode = .byClipping
            addSubview(valueLabel)
        }

        topDot.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        topDot.textColor = .systemRed
        topDot.alignment = .center
        bottomDot.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        bottomDot.textColor = .systemBlue
        bottomDot.alignment = .center
        addSubview(topDot)
        addSubview(bottomDot)
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
    private let contentView: StatusItemContentView
    private var isRemoved = false

    init(metric: SystemMonitorMetric, statusBar: NSStatusBar = .system) {
        item = statusBar.statusItem(withLength: Self.width(for: metric))
        contentView = StatusItemContentView(metric: metric)
        StatusBarController.configureStatusItem(item)

        guard let button = item.button else { return }
        button.image = nil
        button.title = ""
        contentView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: button.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        button.sendAction(on: [.leftMouseUp])
        button.target = actionTarget
        button.action = #selector(ActionTarget.performAction)
    }

    func update(_ presentation: SystemMonitorStatusItemPresentation) {
        guard let button = item.button else { return }
        contentView.update(presentation)
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
