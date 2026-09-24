import ComposableArchitecture
import SwiftUI
import SystemMonitor
import Utilities

enum SectionBar {
    enum Section: CaseIterable, Hashable {
        case controls
        case authenticator
        case soundMixer
        case systemMonitor

        var title: String {
            switch self {
            case .controls: "Controls".localized()
            case .authenticator: "Authenticator".localized()
            case .soundMixer: "Sound Mixer".localized()
            case .systemMonitor: "System Monitor".localized()
            }
        }

        var symbolName: String {
            switch self {
            case .controls: "switch.2"
            case .authenticator: "key.viewfinder"
            case .soundMixer: "slider.horizontal.3"
            case .systemMonitor: "waveform.path.ecg"
            }
        }
    }

    static func sections(authenticator: Bool, soundMixer: Bool) -> [Section] {
        var sections: [Section] = [.controls]
        if authenticator { sections.append(.authenticator) }
        if soundMixer { sections.append(.soundMixer) }
        sections.append(.systemMonitor)
        return sections
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

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let spacingWidth = spacing * CGFloat(max(0, sections.count - 1))
            let segmentWidth = max(0, (proxy.size.width - spacingWidth) / CGFloat(max(1, sections.count)))
            let selectedIndex = sections.firstIndex(of: selection) ?? 0

            ZStack(alignment: .leading) {
                selectionIndicator
                    .frame(width: segmentWidth, height: 30)
                    .offset(x: CGFloat(selectedIndex) * (segmentWidth + spacing))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HStack(spacing: spacing) {
                    ForEach(sections, id: \.self) { section in
                        sectionButton(section)
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selection)
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

    private func sectionButton(_ section: SectionBar.Section) -> some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.32)
            withAnimation(animation) {
                selection = section
            }
        } label: {
            Label(section.title, systemImage: section.symbolName)
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

struct SystemMonitorPanelContainer: View {
    @State private var store: StoreOf<SystemMonitorReducer>

    init() {
        _store = State(initialValue: Store(initialState: SystemMonitorReducer.State()) {
            SystemMonitorReducer()
        } withDependencies: {
            $0.systemMonitor = MacSystemMonitorCollector.liveClient()
        })
    }

    var body: some View {
        SystemMonitorPanelView(store: store)
    }
}

struct SystemMonitorPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: StoreOf<SystemMonitorReducer>
    @State private var preferences = Preferences.shared.systemMonitorPreferences

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = store.snapshot {
                ForEach(visibleMetrics, id: \.self) { metric in
                    metricCard(metric, snapshot: snapshot, store: $store)
                }
            } else if let failure = store.lastFailure {
                ContentUnavailableView(
                    "System Monitor Unavailable".localized(),
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ProgressView("Loading system status…".localized())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
        }
        .padding(15)
        .onAppear {
            store.send(.visibilityChanged(true))
        }
        .onDisappear {
            store.send(.visibilityChanged(false))
        }
        .onReceive(NotificationCenter.default.publisher(for: .systemMonitorPreferencesChanged)) { notification in
            guard let updated = notification.object as? SystemMonitorPreferences else { return }
            preferences = updated
        }
    }

    private var visibleMetrics: [SystemMonitorMetric] {
        SystemMonitorMetric.allCases.filter(preferences.enabledPanelMetrics.contains)
    }

    private var processorAccent: Color {
        colorScheme == .dark
            ? Color(red: 0.20, green: 0.68, blue: 1)
            : .accentColor
    }

    @ViewBuilder
    private func metricCard(
        _ metric: SystemMonitorMetric,
        snapshot: SystemMonitorSnapshot,
        store: Bindable<StoreOf<SystemMonitorReducer>>
    ) -> some View {
        switch metric {
        case .cpu:
            availabilityCard(
                title: "CPU".localized(),
                symbolName: "cpu",
                availability: snapshot.cpuUsage,
                temperature: snapshot.cpuTemperatureCelsius,
                processor: snapshot.hardware.cpu,
                detail: { cpuDetails(snapshot, store: store) }
            ) { usage in
                metricSummary(usage, history: store.wrappedValue.history.snapshots.map { $0.cpuUsage.value ?? 0 })
            }
        case .gpu:
            availabilityCard(
                title: "GPU".localized(),
                symbolName: "rectangle.3.group",
                availability: snapshot.gpuUsage,
                temperature: snapshot.gpuTemperatureCelsius,
                processor: snapshot.hardware.gpu,
                detail: { EmptyView() }
            ) { usage in
                metricSummary(usage, history: store.wrappedValue.history.snapshots.map { $0.gpuUsage.value ?? 0 })
            }
        case .memory:
            memoryCard(snapshot, store: store)
        case .disk:
            diskCard(snapshot.disks)
        case .network:
            networkCard(snapshot, store: store)
        }
    }

    @ViewBuilder
    private func availabilityCard<Detail: View, Content: View>(
        title: String,
        symbolName: String,
        availability: MetricAvailability<Double>,
        temperature: MetricAvailability<Double>,
        processor: SystemMonitorProcessor,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder content: (Double) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metricHeader(title, symbolName: symbolName, tint: processorAccent)
            processorDetails(processor, metricName: title)
            switch availability {
            case let .available(value):
                content(value)
                temperatureLabel(temperature)
                detail()
            case .unavailable:
                Text("Unavailable".localized())
                    .foregroundStyle(.secondary)
                temperatureLabel(temperature)
            }
        }
        .metricCardSurface()
    }

    private func metricSummary(_ usage: Double, history: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(SystemMonitorFormatter.percentage(usage))
                    .font(.title2.bold())
                Text("Current usage".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: usage)
                .tint(processorAccent)
            SystemMonitorChartView(
                points: history,
                tint: processorAccent,
                accessibilityLabel: "Usage history".localized(),
                valueDescription: SystemMonitorFormatter.percentage
            )
        }
    }

    private func cpuDetails(
        _ snapshot: SystemMonitorSnapshot,
        store: Bindable<StoreOf<SystemMonitorReducer>>
    ) -> some View {
        DisclosureGroup(
            "Top Processes".localized(),
            isExpanded: expansionBinding(for: .cpu, store: store)
        ) {
            processRows(snapshot.processes, metric: .cpu)
        }
    }

    private func memoryCard(
        _ snapshot: SystemMonitorSnapshot,
        store: Bindable<StoreOf<SystemMonitorReducer>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metricHeader("Memory".localized(), symbolName: "memorychip", tint: .mint)
            switch snapshot.memory {
            case let .available(memory):
                HStack(alignment: .firstTextBaseline) {
                    Text(SystemMonitorFormatter.percentage(memory.usage))
                        .font(.title2.bold())
                    Text("%@ / %@".localizedFormat(
                        SystemMonitorFormatter.bytes(bytes: Double(memory.usedBytes)),
                        SystemMonitorFormatter.bytes(bytes: Double(memory.totalBytes))
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                ProgressView(value: memory.usage)
                    .tint(.mint)
                SystemMonitorChartView(
                    points: store.wrappedValue.history.snapshots.map { $0.memory.value?.usage ?? 0 },
                    tint: .mint,
                    accessibilityLabel: "Memory usage history".localized(),
                    valueDescription: SystemMonitorFormatter.percentage
                )
                Label(
                    SystemMonitorMemoryPressurePresentation.description(memory.pressure),
                    systemImage: memoryPressureSymbol(memory.pressure)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                DisclosureGroup(
                    "Top Processes".localized(),
                    isExpanded: expansionBinding(for: .memory, store: store)
                ) {
                    processRows(snapshot.processes, metric: .memory)
                }
            case .unavailable:
                Text("Unavailable".localized()).foregroundStyle(.secondary)
            }
        }
        .metricCardSurface()
    }

    private func diskCard(_ disks: [SystemMonitorDisk]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metricHeader("Disk".localized(), symbolName: "internaldrive", tint: .orange)
            if disks.isEmpty {
                Text("Unavailable".localized()).foregroundStyle(.secondary)
            } else {
                ForEach(disks) { disk in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(disk.name).lineLimit(1)
                            Spacer()
                            Text(SystemMonitorFormatter.percentage(disk.usage))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: disk.usage).tint(.orange)
                        Text("%@ / %@".localizedFormat(
                            SystemMonitorFormatter.bytes(bytes: Double(disk.usedBytes)),
                            SystemMonitorFormatter.bytes(bytes: Double(disk.totalBytes))
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .metricCardSurface()
    }

    private func networkCard(
        _ snapshot: SystemMonitorSnapshot,
        store: Bindable<StoreOf<SystemMonitorReducer>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metricHeader("Network".localized(), symbolName: "network", tint: .blue)
            switch snapshot.network {
            case let .available(network):
                HStack(alignment: .top, spacing: 10) {
                    networkRateColumn(
                        title: "Download".localized(),
                        historyTitle: "Download history".localized(),
                        rate: network.downloadBytesPerSecond,
                        points: store.wrappedValue.history.snapshots.map {
                            $0.network.value?.downloadBytesPerSecond ?? 0
                        },
                        tint: .blue
                    )
                    networkRateColumn(
                        title: "Upload".localized(),
                        historyTitle: "Upload history".localized(),
                        rate: network.uploadBytesPerSecond,
                        points: store.wrappedValue.history.snapshots.map {
                            $0.network.value?.uploadBytesPerSecond ?? 0
                        },
                        tint: .pink
                    )
                }
                DisclosureGroup(
                    "Network Details".localized(),
                    isExpanded: expansionBinding(for: .network, store: store)
                ) {
                    networkDetails(network.details)
                        .padding(.top, 6)
                }
            case .unavailable:
                Text("Unavailable".localized()).foregroundStyle(.secondary)
            }
        }
        .metricCardSurface()
    }

    @ViewBuilder
    private func networkDetails(_ details: SystemMonitorNetworkDetails?) -> some View {
        if let details {
            VStack(alignment: .leading, spacing: 12) {
                if details.interfaces.isEmpty {
                    Text("No active Wi-Fi or Ethernet interface".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(details.interfaces.enumerated()), id: \.element.id) { index, interface in
                        if index > 0 { Divider() }
                        networkInterfaceDetails(interface)
                    }
                }

                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Addresses".localized(), systemImage: "network.badge.shield.half.filled")
                        .font(.caption.weight(.semibold))
                    networkDetailRow(
                        "Public IPv4".localized(),
                        value: details.publicIPv4Address ?? "Unavailable".localized()
                    )
                    networkDetailRow(
                        "Public IPv6".localized(),
                        value: details.publicIPv6Address ?? "Unavailable".localized()
                    )
                    Text("Public IP addresses are retrieved from the ipify service.".localized())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Text("Network details unavailable".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func networkInterfaceDetails(_ interface: SystemMonitorNetworkInterface) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(interface.displayName, systemImage: networkInterfaceSymbol(interface.kind))
                .font(.caption.weight(.semibold))

            networkDetailRow("Interface".localized(), value: interface.name)
            networkDetailRow(
                "Status".localized(),
                value: interface.isActive ? "Up".localized() : "Down".localized()
            )
            if let ssid = interface.ssid, ssid.isEmpty == false {
                networkDetailRow("Network".localized(), value: ssid)
            }
            if let signalStrength = interface.signalStrength {
                networkDetailRow("Signal".localized(), value: "%d dBm".localizedFormat(signalStrength))
            }
            if let transmitRate = interface.transmitRateMbps, transmitRate > 0 {
                networkDetailRow(
                    "Transmit rate".localized(),
                    value: "%.0f Mbps".localizedFormat(transmitRate)
                )
            }
            if let macAddress = interface.macAddress {
                networkDetailRow("Hardware address".localized(), value: macAddress)
            }
            if interface.localIPv4Addresses.isEmpty == false {
                networkDetailRow(
                    "Local IPv4".localized(),
                    value: interface.localIPv4Addresses.joined(separator: ", ")
                )
            }
            if interface.localIPv6Addresses.isEmpty == false {
                networkDetailRow(
                    "Local IPv6".localized(),
                    value: interface.localIPv6Addresses.joined(separator: ", ")
                )
            }
        }
    }

    private func networkDetailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func networkInterfaceSymbol(_ kind: SystemMonitorNetworkInterface.Kind) -> String {
        switch kind {
        case .wifi:
            "wifi"
        case .ethernet:
            "cable.connector.horizontal"
        case .other:
            "network"
        }
    }

    private func rateSummary(_ title: String, rate: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(SystemMonitorFormatter.rate(bytesPerSecond: rate))
                .font(.title3.weight(.semibold))
            Label(title, systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(tint)
        }
    }

    private func networkRateColumn(
        title: String,
        historyTitle: String,
        rate: Double,
        points: [Double],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rateSummary(title, rate: rate, tint: tint)
            networkHistorySeries(title: historyTitle, points: points, tint: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func networkHistorySeries(title: String, points: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(tint)
            SystemMonitorChartView(
                points: points,
                tint: tint,
                accessibilityLabel: title,
                valueDescription: { SystemMonitorFormatter.rate(bytesPerSecond: $0) },
                scale: .adaptive
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricHeader(_ title: String, symbolName: String, tint: Color) -> some View {
        Label {
            Text(title)
                .font(.headline)
        } icon: {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func processorDetails(_ processor: SystemMonitorProcessor, metricName: String) -> some View {
        if let model = processor.model.value {
            Text(model)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else {
            Text("%@ model unavailable".localizedFormat(metricName))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        if processor.physicalCoreCount.value == nil, processor.logicalCoreCount.value == nil {
            processorFact("%@ core count unavailable".localizedFormat(metricName))
        } else {
            HStack(spacing: 6) {
                processorFact(processor.physicalCoreCount.value.map { "%d physical cores".localizedFormat($0) } ?? "Physical cores unavailable".localized())
                processorFact(processor.logicalCoreCount.value.map { "%d logical cores".localizedFormat($0) } ?? "Logical cores unavailable".localized())
            }
        }
    }

    private func memoryPressureSymbol(
        _ pressure: MetricAvailability<SystemMonitorMemoryPressure>
    ) -> String {
        switch pressure {
        case .available(.normal):
            "checkmark.circle"
        case .available(.warning):
            "exclamationmark.triangle"
        case .available(.critical):
            "exclamationmark.octagon"
        case .unavailable:
            "questionmark.circle"
        }
    }

    private func processorFact(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.primary.opacity(0.06), in: Capsule())
    }

    private func temperatureLabel(_ temperature: MetricAvailability<Double>) -> some View {
        Text(SystemMonitorTemperaturePresentation.description(temperature))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func processRows(_ processes: [SystemMonitorProcess], metric: SystemMonitorMetric) -> some View {
        if processes.isEmpty {
            Text("No process details available".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(processes) { process in
                HStack {
                    Text(process.name).lineLimit(1)
                    Spacer(minLength: 8)
                    switch metric {
                    case .cpu:
                        Text(process.cpuUsage.value.map(SystemMonitorFormatter.percentage) ?? "Unavailable".localized())
                    case .memory:
                        Text(process.memoryBytes.value.map { SystemMonitorFormatter.bytes(bytes: Double($0)) } ?? "Unavailable".localized())
                    default:
                        EmptyView()
                    }
                }
                .font(.caption)
            }
        }
    }

    private func expansionBinding(
        for metric: SystemMonitorMetric,
        store: Bindable<StoreOf<SystemMonitorReducer>>
    ) -> Binding<Bool> {
        Binding(
            get: { store.wrappedValue.expandedMetrics.contains(metric) },
            set: { isExpanded in
                guard isExpanded != store.wrappedValue.expandedMetrics.contains(metric) else { return }
                store.wrappedValue.send(.toggleExpandedMetric(metric))
            }
        )
    }
}

private extension String {
    func localizedFormat(_ arguments: CVarArg...) -> String {
        String(format: localized(), locale: Locale.current, arguments: arguments)
    }
}

private extension View {
    func metricCardSurface() -> some View {
        self
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.primary.opacity(0.065), .primary.opacity(0.025)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
            }
    }
}
