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
            let plotHeight = max(size.height - 10, 1)
            let baseline = plotHeight

            for fraction in [0.25, 0.5, 0.75] {
                let y = baseline * fraction
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.primary.opacity(0.10)), lineWidth: 0.5)
            }

            var line = Path()
            var area = Path()

            for (index, point) in clamped.enumerated() {
                let location = CGPoint(
                    x: CGFloat(index) * step,
                    y: baseline * (1 - CGFloat(point))
                )
                if index == 0 {
                    line.move(to: location)
                    area.move(to: CGPoint(x: location.x, y: baseline))
                    area.addLine(to: location)
                } else {
                    line.addLine(to: location)
                    area.addLine(to: location)
                }
            }

            area.addLine(to: CGPoint(x: size.width, y: baseline))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.34), tint.opacity(0.015)]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: baseline)
                )
            )
            context.stroke(line, with: .color(tint), lineWidth: 2)

            if let latest = clamped.last {
                let marker = CGPoint(x: size.width, y: baseline * (1 - CGFloat(latest)))
                context.fill(Path(ellipseIn: CGRect(x: marker.x - 3.5, y: marker.y - 3.5, width: 7, height: 7)), with: .color(tint.opacity(0.18)))
                context.stroke(Path(ellipseIn: CGRect(x: marker.x - 3.5, y: marker.y - 3.5, width: 7, height: 7)), with: .color(tint), lineWidth: 2)
            }
        }
        .frame(height: 52)
        .padding(.top, 2)
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
