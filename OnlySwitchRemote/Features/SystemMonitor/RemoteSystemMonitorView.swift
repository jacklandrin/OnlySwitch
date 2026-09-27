import ComposableArchitecture
import Foundation
import RemoteCore
import SwiftUI
import UIKit

struct RemoteSystemMonitorView: View {
    enum Layout: Equatable { case list, grid(columns: Int) }

    @Bindable var store: StoreOf<RemoteSystemMonitorFeature>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

    static func layout(for idiom: UIUserInterfaceIdiom, dynamicTypeSize: DynamicTypeSize) -> Layout {
        guard idiom == .pad, dynamicTypeSize.isAccessibilitySize == false else { return .list }
        return .grid(columns: 2)
    }

    var body: some View {
        Group {
            if store.layout?.orderedVisibleMetrics.isEmpty == true {
                ContentUnavailableView {
                    Label("No System Monitor Widgets", systemImage: "rectangle.stack.badge.minus")
                } description: {
                    Text("Choose the widgets shown on this Mac.")
                } actions: {
                    Button("Configure System Monitor") {
                        store.send(.configureButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if let snapshot = store.snapshot {
                ScrollView {
                    monitorCardsContainer(snapshot)
                        .padding(20)
                        .padding(.bottom, RemotePageTabBar.contentBottomInset)
                }
            } else if let message = store.availabilityMessage {
                ContentUnavailableView(
                    "System Monitor Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            } else if store.selectedMacID == nil {
                ContentUnavailableView(
                    "No Mac Selected",
                    systemImage: "desktopcomputer",
                    description: Text("Select a paired Mac from the navigation bar.")
                )
            } else if store.connectionState != .authenticated {
                ContentUnavailableView(
                    "System Monitor Unavailable",
                    systemImage: "wifi.slash",
                    description: Text("The selected Mac is offline.")
                )
            } else {
                ProgressView("Loading system status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("System Monitor")
    }

    @ViewBuilder
    private func monitorCardsContainer(_ snapshot: SystemMonitorSnapshot) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                monitorCards(snapshot)
            }
        } else {
            monitorCards(snapshot)
        }
    }

    @ViewBuilder
    private func monitorCards(_ snapshot: SystemMonitorSnapshot) -> some View {
        let cards = store.layout?.orderedVisibleMetrics ?? SystemMonitorMetric.allCases
        switch Self.layout(for: idiom, dynamicTypeSize: dynamicTypeSize) {
        case .list:
            LazyVStack(spacing: 16) {
                ForEach(cards, id: \.self) { metric in metricCard(metric, snapshot: snapshot) }
            }
        case let .grid(columnCount):
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columnCount),
                spacing: 16
            ) {
                ForEach(cards, id: \.self) { metric in metricCard(metric, snapshot: snapshot) }
            }
        }
    }

    @ViewBuilder
    private func metricCard(_ metric: SystemMonitorMetric, snapshot: SystemMonitorSnapshot) -> some View {
        RemoteSystemMonitorCardSurface {
            VStack(alignment: .leading, spacing: 12) {
                switch metric {
                case .cpu:
                    RemoteSystemMonitorGaugeView(
                        presentation: RemoteSystemMonitorGaugePresentation(
                            title: metric.displayTitleKey,
                            usage: snapshot.cpuUsage
                        ),
                        symbol: symbol(for: metric),
                        accent: .cpu
                    )
                    processorCard(
                        temperature: snapshot.cpuTemperatureCelsius,
                        processor: snapshot.hardware.cpu,
                        values: store.history.snapshots.compactMap(\.cpuUsage.value)
                    )
                    disclosureButton(metric, title: "Top Processes")
                    if store.expandedMetrics.contains(metric) {
                        processRows(snapshot.processes, value: { availability($0.cpuUsage, format: percentage) })
                    }
                case .gpu:
                    RemoteSystemMonitorGaugeView(
                        presentation: RemoteSystemMonitorGaugePresentation(
                            title: metric.displayTitleKey,
                            usage: snapshot.gpuUsage
                        ),
                        symbol: symbol(for: metric),
                        accent: .gpu
                    )
                    processorCard(
                        temperature: snapshot.gpuTemperatureCelsius,
                        processor: snapshot.hardware.gpu,
                        values: store.history.snapshots.compactMap(\.gpuUsage.value)
                    )
                case .memory:
                    RemoteSystemMonitorGaugeView(
                        presentation: RemoteSystemMonitorGaugePresentation(
                            title: metric.displayTitleKey,
                            usage: snapshot.memory.value.map { .available($0.usage) } ?? .unavailable
                        ),
                        symbol: symbol(for: metric),
                        accent: .memory
                    )
                    memoryCard(snapshot)
                case .disk:
                    metricHeader(metric)
                    diskCard(snapshot.disks)
                case .network:
                    metricHeader(metric)
                    networkCard(snapshot)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func processorCard(
        temperature: MetricAvailability<Double>,
        processor: SystemMonitorProcessor,
        values: [Double]
    ) -> some View {
        RemoteSystemMonitorChartView(values: values, title: "Current usage")
        detailRow("Temperature", temperatureDescription(temperature))
        detailRow("Model", availability(processor.model) { $0 })
        detailRow("Physical Cores", availability(processor.physicalCoreCount) { String($0) })
        detailRow("Logical Cores", availability(processor.logicalCoreCount) { String($0) })
    }

    @ViewBuilder
    private func memoryCard(_ snapshot: SystemMonitorSnapshot) -> some View {
        switch snapshot.memory {
        case let .available(memory):
            RemoteSystemMonitorChartView(
                values: store.history.snapshots.compactMap { $0.memory.value?.usage },
                title: "Memory usage"
            )
            detailRow("Used", "\(bytes(Double(memory.usedBytes))) / \(bytes(Double(memory.totalBytes)))")
            detailRow("Compressed", bytes(Double(memory.compressedBytes)))
            detailRow("Cached", bytes(Double(memory.cachedBytes)))
            detailRow("Swap Used", bytes(Double(memory.swapUsedBytes)))
            detailRow("Memory Pressure", memoryPressure(memory.pressure))
            disclosureButton(.memory, title: "Top Processes")
            if store.expandedMetrics.contains(.memory) {
                processRows(snapshot.processes, value: { availability($0.memoryBytes) { bytes(Double($0)) } })
            }
        case .unavailable:
            Text("Unavailable").foregroundStyle(.secondary)
        }
    }

    private func metricHeader(_ metric: SystemMonitorMetric) -> some View {
        Label(LocalizedStringKey(metric.displayTitleKey), systemImage: symbol(for: metric))
            .font(.headline)
    }

    @ViewBuilder
    private func diskCard(_ disks: [SystemMonitorDisk]) -> some View {
        if disks.isEmpty {
            Text("Unavailable").foregroundStyle(.secondary)
        } else {
            ForEach(disks) { disk in
                let presentation = Self.diskPresentation(disk)
                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.name).font(.subheadline.weight(.semibold))
                    ProgressView(value: presentation.usage)
                    ForEach(presentation.rows) { row in
                        detailRow(LocalizedStringKey(row.title), row.value)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func networkCard(_ snapshot: SystemMonitorSnapshot) -> some View {
        switch snapshot.network {
        case let .available(network):
            detailRow("Download", rate(network.downloadBytesPerSecond))
            detailRow("Upload", rate(network.uploadBytesPerSecond))
            detailRow("Downloaded", bytes(Double(network.totalDownloadedBytes)))
            detailRow("Uploaded", bytes(Double(network.totalUploadedBytes)))
            RemoteSystemMonitorChartView(
                values: store.history.snapshots.compactMap { $0.network.value?.downloadBytesPerSecond },
                title: "Network activity"
            )
            disclosureButton(.network, title: "Network Details")
            if store.expandedMetrics.contains(.network) {
                networkDetails(network.details)
            }
        case .unavailable:
            Text("Unavailable").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func networkDetails(_ details: SystemMonitorNetworkDetails?) -> some View {
        if let details {
            if let address = details.publicIPv4Address { addressRow("Public IPv4", address) }
            if let address = details.publicIPv6Address { addressRow("Public IPv6", address) }
            ForEach(details.interfaces) { interface in
                VStack(alignment: .leading, spacing: 4) {
                    Text(interface.displayName).font(.subheadline.weight(.semibold))
                    if let ssid = interface.ssid { detailRow("Wi-Fi", ssid) }
                    if let signal = interface.signalStrength { detailRow("Signal", "\(signal)%") }
                    if let rate = interface.transmitRateMbps { detailRow("Transmit Rate", "\(rate.formatted()) Mbps") }
                    if let address = interface.macAddress { addressRow("MAC", address) }
                    ForEach(interface.localIPv4Addresses, id: \.self) { addressRow("IPv4", $0) }
                    ForEach(interface.localIPv6Addresses, id: \.self) { addressRow("IPv6", $0) }
                }
            }
        } else {
            Text("Unavailable").foregroundStyle(.secondary)
        }
    }

    private func disclosureButton(_ metric: SystemMonitorMetric, title: LocalizedStringKey) -> some View {
        Button {
            store.send(.toggleExpandedMetric(metric))
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: store.expandedMetrics.contains(metric) ? "chevron.up" : "chevron.down")
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(store.expandedMetrics.contains(metric) ? .isSelected : [])
    }

    private func processRows(
        _ processes: [SystemMonitorProcess],
        value: @escaping (SystemMonitorProcess) -> String
    ) -> some View {
        ForEach(processes.prefix(8)) { process in
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: process.name).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value(process)).multilineTextAlignment(.trailing)
            }
            .font(.caption)
        }
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func addressRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        detailRow(title, value).textSelection(.enabled)
    }

    private func symbol(for metric: SystemMonitorMetric) -> String {
        switch metric {
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        }
    }

    private func availability<Value>(_ value: MetricAvailability<Value>, format: (Value) -> String) -> String {
        value.value.map(format) ?? String(localized: "Unavailable")
    }

    private func temperatureDescription(_ value: MetricAvailability<Double>) -> String {
        availability(value) { "\($0.formatted(.number.precision(.fractionLength(0)))) °C" }
    }

    private func memoryPressure(_ pressure: MetricAvailability<SystemMonitorMemoryPressure>) -> String {
        availability(pressure) {
            switch $0 {
            case .normal: String(localized: "Normal")
            case .warning: String(localized: "Warning")
            case .critical: String(localized: "Critical")
            }
        }
    }

    private func percentage(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(max(value, 0)),
            countStyle: .file
        )
    }

    private func rate(_ value: Double) -> String {
        "\(bytes(value))/s"
    }

    static func diskPresentation(_ disk: SystemMonitorDisk) -> RemoteSystemMonitorDiskPresentation {
        RemoteSystemMonitorDiskPresentation(
            name: disk.name,
            usage: disk.usage,
            rows: [
                .init(
                    title: "Used",
                    value: "\(formattedBytes(disk.usedBytes)) / \(formattedBytes(disk.totalBytes))"
                )
            ]
        )
    }

    private static func formattedBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}

struct RemoteSystemMonitorDiskPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let title: String
        let value: String

        var id: String { title }
    }

    let name: String
    let usage: Double
    let rows: [Row]
}
