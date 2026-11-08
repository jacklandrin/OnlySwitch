import ComposableArchitecture
import SwiftUI
import SystemMonitor

extension SystemMonitorPanelView {
    func networkCard(
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
}
