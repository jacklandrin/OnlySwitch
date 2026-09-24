import SwiftUI
import SystemMonitor

struct SystemMonitorSettingsView: View {
    @StateObject private var viewModel = SystemMonitorSettingsViewModel()

    var body: some View {
        Form {
            Section {
                ForEach(SystemMonitorMetric.allCases, id: \.self) { metric in
                    Toggle(metric.displayTitleKey.localized(), isOn: viewModel.panelMetricBinding(for: metric))
                }
                Text("GPU readings use undocumented macOS interfaces and may stop working after a system update.".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Dashboard".localized())
            } footer: {
                Text("Choose the system information shown in the System Monitor dashboard.".localized())
            }

            Section {
                ForEach(SystemMonitorMetric.allCases, id: \.self) { metric in
                    Toggle(metric.displayTitleKey.localized(), isOn: viewModel.menuBarMetricBinding(for: metric))
                }
            } header: {
                Text("Menu Bar Indicators".localized())
            } footer: {
                Text("Enabled indicators keep the monitor sampling while the popover is closed.".localized())
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
    }
}
