import ComposableArchitecture
import SwiftUI
import SystemMonitor

extension SystemMonitorPanelView {
    @ViewBuilder
    func processorDetails(_ processor: SystemMonitorProcessor, metricName: String) -> some View {
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

    func memoryPressureSymbol(
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

    func temperatureLabel(_ temperature: MetricAvailability<Double>) -> some View {
        Text(SystemMonitorTemperaturePresentation.description(temperature))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    func processRows(
        _ processes: [SystemMonitorProcess],
        metric: SystemMonitorMetric,
        store: Bindable<StoreOf<SystemMonitorReducer>>
    ) -> some View {
        if processes.isEmpty {
            Text("No process details available".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(processes) { process in
                let value = processValue(process, metric: metric)
                let rowID = "\(metric.rawValue)-\(process.pid)"
                if process.activationTarget != nil {
                    Button {
                        store.wrappedValue.send(.processTapped(process))
                    } label: {
                        processRow(process, value: value)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .focused($focusedProcessRow, equals: rowID)
                    .background(
                        Color.primary.opacity(
                            hoveredProcessRow == rowID || focusedProcessRow == rowID ? 0.08 : 0
                        ),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .onHover { isHovered in
                        hoveredProcessRow = isHovered ? rowID : nil
                    }
                    .accessibilityLabel(Text("Activate %@".localizedFormat(process.name)))
                    .accessibilityValue(Text(value))
                    .accessibilityInputLabels([Text(process.name)])
                    .accessibilityHint(Text("Activates the application for this process".localized()))
                    .help("Activate %@".localizedFormat(process.name))
                } else {
                    processRow(process, value: value)
                }
            }
        }
    }

    private func processRow(_ process: SystemMonitorProcess, value: String) -> some View {
        HStack {
            Text(process.name).lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func processValue(_ process: SystemMonitorProcess, metric: SystemMonitorMetric) -> String {
        switch metric {
        case .cpu:
            process.cpuUsage.value.map(SystemMonitorFormatter.percentage) ?? "Unavailable".localized()
        case .memory:
            process.memoryBytes.value.map { SystemMonitorFormatter.bytes(bytes: Double($0)) }
                ?? "Unavailable".localized()
        default:
            "Unavailable".localized()
        }
    }

    func expansionBinding(
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

extension String {
    func localizedFormat(_ arguments: CVarArg...) -> String {
        String(format: localized(), locale: Locale.current, arguments: arguments)
    }
}

extension View {
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
