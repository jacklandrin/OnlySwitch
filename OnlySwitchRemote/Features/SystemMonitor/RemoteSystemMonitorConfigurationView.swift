import ComposableArchitecture
import RemoteCore
import SwiftUI

struct RemoteSystemMonitorConfigurationView: View {
    @Bindable var store: StoreOf<RemoteSystemMonitorConfigurationFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(store.layout.order, id: \.self) { metric in
                    Button {
                        store.send(.setVisible(
                            metric,
                            store.layout.visibleMetrics.contains(metric) == false
                        ))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: store.layout.visibleMetrics.contains(metric)
                                ? "checkmark.circle.fill"
                                : "circle")
                                .foregroundStyle(store.layout.visibleMetrics.contains(metric)
                                    ? Color.accentColor
                                    : Color.secondary)
                                .accessibilityHidden(true)
                            Image(systemName: Self.symbol(for: metric))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            Text(LocalizedStringKey(metric.displayTitleKey))
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(store.layout.visibleMetrics.contains(metric) ? "Shown" : "Hidden")
                }
                .onMove { store.send(.move($0, $1)) }
            } header: {
                Text("Show Widgets")
            } footer: {
                Text("Choose the widgets shown on this Mac.")
            }

            if store.isSaveFailed {
                Section {
                    Button("Retry Saving System Monitor Layout", systemImage: "arrow.clockwise") {
                        store.send(.retrySave)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Configure System Monitor")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
            }
        }
    }

    private static func symbol(for metric: SystemMonitorMetric) -> String {
        switch metric {
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        }
    }
}
