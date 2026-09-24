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

struct SystemMonitorSectionBar: View {
    let sections: [SectionBar.Section]
    @Binding var selection: SectionBar.Section

    var body: some View {
        HStack(spacing: 4) {
            ForEach(sections, id: \.self) { section in
                Button {
                    selection = section
                } label: {
                    Label(section.title, systemImage: section.symbolName)
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? .primary : .secondary)
                .background {
                    Capsule()
                        .fill(selection == section ? Color.accentColor.opacity(0.18) : .clear)
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    selection == section ? Color.accentColor.opacity(0.32) : .clear,
                                    lineWidth: 1
                                )
                        }
                }
                .accessibilityLabel(Text(section.title))
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .accessibilityHint(Text("Shows the \(section.title) section".localized()))
                .help(Text(section.title))
            }
        }
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
            store.send(.menuBarMetricsChanged(preferences.menuBarMetrics))
            store.send(.visibilityChanged(true))
        }
        .onDisappear {
            store.send(.visibilityChanged(false))
        }
        .onReceive(NotificationCenter.default.publisher(for: .systemMonitorPreferencesChanged)) { notification in
            guard let updated = notification.object as? SystemMonitorPreferences else { return }
            preferences = updated
            store.send(.menuBarMetricsChanged(updated.menuBarMetrics))
        }
    }

    private var visibleMetrics: [SystemMonitorMetric] {
        SystemMonitorMetric.allCases.filter(preferences.enabledPanelMetrics.contains)
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
            metricHeader(title, symbolName: symbolName, tint: .accentColor)
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
                .tint(.accentColor)
            SystemMonitorChartView(
                points: history,
                tint: .accentColor,
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
                        temperatureLabel(disk.temperatureCelsius)
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
                HStack {
                    rateSummary("Download".localized(), rate: network.downloadBytesPerSecond, tint: .blue)
                    Spacer()
                    rateSummary("Upload".localized(), rate: network.uploadBytesPerSecond, tint: .pink)
                }
                networkHistory(store.wrappedValue.history.snapshots)
                DisclosureGroup(
                    "Network Details".localized(),
                    isExpanded: expansionBinding(for: .network, store: store)
                ) {
                    Text("Per-process network usage is unavailable through public macOS APIs.".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .unavailable:
                Text("Unavailable".localized()).foregroundStyle(.secondary)
            }
        }
        .metricCardSurface()
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

    private func networkHistory(_ snapshots: [SystemMonitorSnapshot]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            networkHistorySeries(
                title: "Download history".localized(),
                points: snapshots.map { $0.network.value?.downloadBytesPerSecond ?? 0 },
                tint: .blue
            )
            networkHistorySeries(
                title: "Upload history".localized(),
                points: snapshots.map { $0.network.value?.uploadBytesPerSecond ?? 0 },
                tint: .pink
            )
        }
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
            Text("\(metricName) model unavailable".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        if processor.physicalCoreCount.value == nil, processor.logicalCoreCount.value == nil {
            processorFact("\(metricName) core count unavailable".localized())
        } else {
            HStack(spacing: 6) {
                processorFact(processor.physicalCoreCount.value.map { "\($0) physical cores".localized() } ?? "Physical cores unavailable".localized())
                processorFact(processor.logicalCoreCount.value.map { "\($0) logical cores".localized() } ?? "Logical cores unavailable".localized())
            }
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
