import Charts
import SwiftUI

struct RemoteSystemMonitorChartView: View {
    let values: [Double]
    let title: LocalizedStringKey

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("Sample", index), y: .value("Value", value))
                .foregroundStyle(.tint.opacity(0.18))
            LineMark(x: .value("Sample", index), y: .value("Value", value))
                .foregroundStyle(.tint)
        }
        .chartYScale(domain: 0 ... max(1, values.max() ?? 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(
            values.last.map { $0.formatted(.percent.precision(.fractionLength(0))) }
                ?? String(localized: "Unavailable")
        )
    }
}
