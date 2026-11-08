import AppKit
import ComposableArchitecture
import SwiftUI
import SystemMonitor
import Utilities

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
    @State var hoveredProcessRow: String?
    @FocusState var focusedProcessRow: String?

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: preferences.isCompactMode ? 6 : 12) {
            if let snapshot = store.snapshot {
                ForEach(visibleMetrics, id: \.self) { metric in
                    if preferences.isCompactMode {
                        SystemMonitorCompactMetricView(metric: metric, snapshot: snapshot)
                    } else {
                        metricCard(metric, snapshot: snapshot, store: $store)
                    }
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
        .alert(
            "Application unavailable".localized(),
            isPresented: Binding(
                get: { store.processActivationFailure != nil },
                set: { isPresented in
                    if isPresented == false {
                        store.send(.dismissProcessActivationFailure)
                    }
                }
            )
        ) {
            Button("OK".localized()) {
                store.send(.dismissProcessActivationFailure)
            }
        } message: {
            Text("The application for this process is no longer available.".localized())
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
            processRows(snapshot.processes, metric: .cpu, store: store)
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
                    processRows(snapshot.processes, metric: .memory, store: store)
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

    func metricHeader(_ title: String, symbolName: String, tint: Color) -> some View {
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
}
