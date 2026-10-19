import SwiftUI
import SystemMonitor

struct SystemMonitorCompactMetricView: View {
    @Environment(\.colorScheme) private var colorScheme
    let metric: SystemMonitorMetric
    let snapshot: SystemMonitorSnapshot

    var body: some View {
        VStack(spacing: 8) {
            switch metric {
            case .cpu:
                usageRow("CPU".localized(), symbol: "cpu", usage: snapshot.cpuUsage.value, tint: processorAccent)
            case .gpu:
                usageRow("GPU".localized(), symbol: "rectangle.3.group", usage: snapshot.gpuUsage.value, tint: processorAccent)
            case .memory:
                usageRow("Memory".localized(), symbol: "memorychip", usage: snapshot.memory.value?.usage, tint: .mint)
            case .disk:
                if snapshot.disks.isEmpty {
                    usageRow("Disk".localized(), symbol: "internaldrive", usage: nil, tint: .orange)
                } else {
                    ForEach(snapshot.disks) { disk in
                        usageRow(disk.name, symbol: "internaldrive", usage: disk.usage, tint: .orange)
                    }
                }
            case .network:
                HStack(spacing: 10) {
                    metricLabel("Network".localized(), symbol: "network", tint: .blue)
                    Spacer(minLength: 4)
                    if let network = snapshot.network.value {
                        Label(SystemMonitorFormatter.rate(bytesPerSecond: network.downloadBytesPerSecond), systemImage: "arrow.down")
                            .lineLimit(1)
                            .foregroundStyle(.blue)
                            .accessibilityLabel(Text("Download".localized()))
                            .accessibilityValue(Text(SystemMonitorFormatter.rate(bytesPerSecond: network.downloadBytesPerSecond)))
                        Label(SystemMonitorFormatter.rate(bytesPerSecond: network.uploadBytesPerSecond), systemImage: "arrow.up")
                            .lineLimit(1)
                            .foregroundStyle(.pink)
                            .accessibilityLabel(Text("Upload".localized()))
                            .accessibilityValue(Text(SystemMonitorFormatter.rate(bytesPerSecond: network.uploadBytesPerSecond)))
                    } else {
                        Text("Unavailable".localized()).foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var processorAccent: Color {
        colorScheme == .dark ? Color(red: 0.20, green: 0.68, blue: 1) : .accentColor
    }

    private func metricLabel(_ title: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(title).lineLimit(1)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
        .fontWeight(.medium)
    }

    private func usageRow(_ title: String, symbol: String, usage: Double?, tint: Color) -> some View {
        HStack(spacing: 10) {
            metricLabel(title, symbol: symbol, tint: tint)
                .frame(width: 90, alignment: .leading)
            if let usage {
                let boundedUsage = usage.isFinite ? min(max(usage, 0), 1) : 0
                GeometryReader { geometry in
                    Capsule()
                        .fill(.primary.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(tint)
                                .frame(width: geometry.size.width * boundedUsage)
                        }
                }
                .frame(height: 5)
                .accessibilityHidden(true)
                Text(SystemMonitorFormatter.percentage(boundedUsage))
                    .monospacedDigit()
                    .frame(minWidth: 38, alignment: .trailing)
            } else {
                Spacer(minLength: 4)
                Text("Unavailable".localized()).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
