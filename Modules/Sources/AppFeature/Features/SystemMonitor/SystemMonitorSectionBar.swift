import AppKit
import SwiftUI
import SystemMonitor

enum SectionBar {
    /// Raw values are persisted in `UserDefaults.Key.tabOrder`; keep them stable.
    enum Section: String, CaseIterable, Hashable {
        case controls
        case authenticator
        case soundMixer
        case systemMonitor
        case codexUsage
        case claudeUsage
        case aphrodite
        case xcodeCleaner
        case appUninstaller
        case screenshots
        case brightness
        case schedules

        var allowsOutsideClickDismissal: Bool { self != .appUninstaller && self != .screenshots }

        var title: String {
            switch self {
            case .controls: "Controls".localized()
            case .authenticator: "Authenticator".localized()
            case .soundMixer: "Sound Mixer".localized()
            case .systemMonitor: "System Monitor".localized()
            case .codexUsage: "Codex Usage".localized()
            case .claudeUsage: "Claude Usage".localized()
            case .aphrodite: "Aphrodite".localized()
            case .xcodeCleaner: "Xcode Cleaner".localized()
            case .appUninstaller: "App Uninstaller".localized()
            case .screenshots: "Screenshots & Record".localized()
            case .brightness: "Brightness".localized()
            case .schedules: "Schedules".localized()
            }
        }

        var symbolName: String {
            switch self {
            case .controls: "switch.2"
            case .authenticator: "key.viewfinder"
            case .soundMixer: "slider.horizontal.3"
            case .systemMonitor: "waveform.path.ecg"
            case .codexUsage: "gauge.with.dots.needle.50percent"
            case .claudeUsage: "gauge.with.dots.needle.50percent"
            case .aphrodite: "sparkles.rectangle.stack"
            case .xcodeCleaner: "hammer.fill"
            case .appUninstaller: "trash.fill"
            case .screenshots: "photo.on.rectangle.angled"
            case .brightness: "sun.max.fill"
            case .schedules: "calendar.badge.clock"
            }
        }

        /// Brand logo from the app asset catalog; sections without one use `symbolName`.
        var assetName: String? {
            switch self {
            case .codexUsage: "openai_logo"
            case .claudeUsage: "claude_logo"
            case .controls, .authenticator, .soundMixer, .systemMonitor, .aphrodite, .xcodeCleaner, .appUninstaller, .screenshots, .brightness, .schedules: nil
            }
        }
    }

    static func sections(
        authenticator: Bool,
        soundMixer: Bool,
        systemMonitor: Bool,
        codexUsage: Bool,
        claudeUsage: Bool = false,
        aphrodite: Bool = false,
        xcodeCleaner: Bool = false,
        appUninstaller: Bool = false,
        screenshots: Bool = false,
        brightness: Bool = false,
        schedules: Bool = false,
        order: [Section] = Section.manageable
    ) -> [Section] {
        let isVisible: [Section: Bool] = [
            .authenticator: authenticator, .soundMixer: soundMixer, .systemMonitor: systemMonitor,
            .codexUsage: codexUsage, .claudeUsage: claudeUsage, .aphrodite: aphrodite,
            .xcodeCleaner: xcodeCleaner, .appUninstaller: appUninstaller, .screenshots: screenshots,
            .brightness: brightness, .schedules: schedules,
        ]
        return [.controls] + order.filter { isVisible[$0] == true }
    }

    /// Optional tabs in the user's saved order. Unknown or repeated ids are dropped, and tabs missing from
    /// the saved order (e.g. added in a later version) follow in their default position.
    static func manageableOrder(from storedOrder: String) -> [Section] {
        var order: [Section] = []
        for id in storedOrder.split(separator: ",") {
            guard let section = Section(rawValue: String(id)), section != .controls, !order.contains(section) else { continue }
            order.append(section)
        }
        return order + Section.manageable.filter { !order.contains($0) }
    }

    static func storedOrder(_ order: [Section]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    static func shouldShowBar(for sections: [Section]) -> Bool {
        sections.count > 1
    }

    /// Single-column list fits at most this many tabs; more scroll horizontally.
    static let singleColumnVisibleSegmentLimit = 5

    /// Number of equal-width segments that fit in the bar; fewer than `sectionCount` means the bar scrolls.
    static func visibleSegmentCount(for sectionCount: Int, limit: Int?) -> Int {
        let count = max(1, sectionCount)
        guard let limit else { return count }
        return min(count, max(1, limit))
    }

    /// Points scrolled per line for wheels that report line-based (imprecise) deltas.
    static let wheelLineScrollDistance: CGFloat = 10

    /// Horizontal content offset change for a wheel event over a scrolling bar, or `nil` to leave the event
    /// alone. Mostly vertical movement scrolls the bar sideways; horizontal swipes keep their native handling.
    static func horizontalScrollDelta(deltaX: CGFloat, deltaY: CGFloat, hasPreciseDeltas: Bool) -> CGFloat? {
        guard deltaY != 0, abs(deltaY) > abs(deltaX) else { return nil }
        return hasPreciseDeltas ? deltaY : deltaY * wheelLineScrollDistance
    }
}

/// Tab icon: an SF Symbol, or a template brand logo sized to sit next to the symbols.
struct SectionBarIcon: View {
    let section: SectionBar.Section
    let logoSize: CGFloat

    var body: some View {
        if let assetName = section.assetName {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
        } else {
            Image(systemName: section.symbolName)
        }
    }
}

enum SystemMonitorTemperaturePresentation {
    static func description(_ temperature: MetricAvailability<Double>) -> String {
        switch temperature {
        case let .available(celsius):
            String(format: "Temperature %.0f °C".localized(), celsius)
        case .unavailable:
            "Temperature unavailable".localized()
        }
    }
}

enum SystemMonitorMemoryPressurePresentation {
    static func description(_ pressure: MetricAvailability<SystemMonitorMemoryPressure>) -> String {
        let value: String
        switch pressure {
        case let .available(status):
            switch status {
            case .normal:
                value = "Normal".localized()
            case .warning:
                value = "Warning".localized()
            case .critical:
                value = "Critical".localized()
            }
        case .unavailable:
            value = "Unavailable".localized()
        }
        return "Memory pressure: %@".localizedFormat(value)
    }
}

struct SystemMonitorSectionBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sections: [SectionBar.Section]
    @Binding var selection: SectionBar.Section
    /// Maximum segments shown at once; when there are more sections the bar scrolls horizontally. `nil` fits all.
    var visibleSegmentLimit: Int? = nil

    private let spacing: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let visibleCount = SectionBar.visibleSegmentCount(for: sections.count, limit: visibleSegmentLimit)
            let spacingWidth = spacing * CGFloat(visibleCount - 1)
            let segmentWidth = max(0, (proxy.size.width - spacingWidth) / CGFloat(visibleCount))

            if visibleCount < sections.count {
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        segments(segmentWidth: segmentWidth)
                            .background(VerticalWheelHorizontalScroller())
                    }
                    .clipShape(Capsule())
                    .onAppear { reader.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { _, newSelection in
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                            reader.scrollTo(newSelection, anchor: .center)
                        }
                    }
                }
            } else {
                segments(segmentWidth: segmentWidth)
            }
        }
        .frame(height: 30)
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
        .padding(.horizontal, 15)
        .accessibilityElement(children: .contain)
    }

    private func segments(segmentWidth: CGFloat) -> some View {
        let selectedIndex = sections.firstIndex(of: selection) ?? 0
        return ZStack(alignment: .leading) {
            selectionIndicator
                .frame(width: segmentWidth, height: 30)
                .offset(x: CGFloat(selectedIndex) * (segmentWidth + spacing))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack(spacing: spacing) {
                ForEach(sections, id: \.self) { section in
                    sectionButton(section)
                        .frame(width: segmentWidth)
                        .id(section)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selection)
    }

    private func sectionButton(_ section: SectionBar.Section) -> some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.32)
            withAnimation(animation) {
                selection = section
            }
        } label: {
            Label { Text(section.title) } icon: { SectionBarIcon(section: section, logoSize: 16) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(selection == section ? .primary : .secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(section.title))
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .accessibilityHint(Text("Shows the %@ section".localizedFormat(section.title)))
        .help(Text(section.title))
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.16)), in: Capsule())
        } else {
            Capsule()
                .fill(.thinMaterial)
                .overlay {
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
        }
    }
}

/// Lets a mouse wheel's vertical movement scroll the enclosing horizontal `ScrollView` of the section bar.
private struct VerticalWheelHorizontalScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ nsView: MonitorView, context: Context) {}

    final class MonitorView: NSView {
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // Local monitors run synchronously on the main thread, so the event never leaves it.
                nonisolated(unsafe) let event = event
                let consumed = MainActor.assumeIsolated { self?.scrollHorizontally(for: event) ?? false }
                return consumed ? nil : event
            }
        }

        /// Returns `true` when the event was turned into horizontal scrolling and should be consumed.
        private func scrollHorizontally(for event: NSEvent) -> Bool {
            guard event.window === window,
                  let scrollView = enclosingScrollView,
                  let documentView = scrollView.documentView,
                  scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)),
                  let delta = SectionBar.horizontalScrollDelta(
                      deltaX: event.scrollingDeltaX,
                      deltaY: event.scrollingDeltaY,
                      hasPreciseDeltas: event.hasPreciseScrollingDeltas
                  ) else { return false }

            let clipView = scrollView.contentView
            let maxX = max(0, documentView.frame.width - clipView.bounds.width)
            var origin = clipView.bounds.origin
            origin.x = min(max(0, origin.x - delta), maxX)
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
            return true
        }
    }
}
