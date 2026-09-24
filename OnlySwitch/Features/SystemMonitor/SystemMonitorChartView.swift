import SwiftUI

/// A compact history graph that deliberately avoids animation: readings update every second and
/// motion would make the current value harder to read, particularly with Reduce Motion enabled.
struct SystemMonitorChartView: View {
    let points: [Double]
    let tint: Color
    let accessibilityLabel: String
    let valueDescription: (Double) -> String

    var body: some View {
        Canvas { context, size in
            guard points.isEmpty == false else { return }

            let clamped = points.map { min(max($0, 0), 1) }
            let step = size.width / CGFloat(max(clamped.count - 1, 1))
            var path = Path()

            for (index, point) in clamped.enumerated() {
                let location = CGPoint(
                    x: CGFloat(index) * step,
                    y: size.height * (1 - CGFloat(point))
                )
                if index == 0 {
                    path.move(to: location)
                } else {
                    path.addLine(to: location)
                }
            }

            context.stroke(path, with: .color(tint), lineWidth: 2)
        }
        .frame(height: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(summary))
    }

    private var summary: String {
        guard let latest = points.last,
              let minimum = points.min(),
              let maximum = points.max()
        else {
            return "No history available".localized()
        }

        return String(
            format: "Latest %@, minimum %@, maximum %@".localized(),
            valueDescription(latest),
            valueDescription(minimum),
            valueDescription(maximum)
        )
    }
}
