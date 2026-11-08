import SwiftUI

/// A compact history graph that deliberately avoids animation: readings update every second and
/// motion would make the current value harder to read, particularly with Reduce Motion enabled.
struct SystemMonitorChartView: View {
    enum Scale {
        case unitInterval
        case adaptive
    }

    let points: [Double]
    let tint: Color
    let accessibilityLabel: String
    let valueDescription: (Double) -> String
    var scale: Scale = .unitInterval

    var body: some View {
        Canvas { context, size in
            guard points.isEmpty == false else { return }

            let normalizer = scale.maximum(for: points)
            let normalized = points.map { min(max($0 / normalizer, 0), 1) }
            let markerRadius: CGFloat = 3.5
            let plotWidth = max(size.width - markerRadius, 1)
            let step = plotWidth / CGFloat(max(normalized.count - 1, 1))
            let plotTop = markerRadius
            let baseline = max(size.height - markerRadius, plotTop)
            let plotHeight = max(baseline - plotTop, 1)

            for fraction in [0.25, 0.5, 0.75] {
                let y = plotTop + (plotHeight * fraction)
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: plotWidth, y: y))
                context.stroke(grid, with: .color(.primary.opacity(0.10)), lineWidth: 0.5)
            }

            var line = Path()
            var area = Path()

            for (index, point) in normalized.enumerated() {
                let location = CGPoint(
                    x: CGFloat(index) * step,
                    y: plotTop + (plotHeight * (1 - CGFloat(point)))
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

            area.addLine(to: CGPoint(x: plotWidth, y: baseline))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.34), tint.opacity(0.015)]),
                    startPoint: CGPoint(x: plotWidth / 2, y: 0),
                    endPoint: CGPoint(x: plotWidth / 2, y: baseline)
                )
            )
            context.stroke(line, with: .color(tint), lineWidth: 2)

            if let latest = normalized.last {
                let marker = CGPoint(x: plotWidth, y: plotTop + (plotHeight * (1 - CGFloat(latest))))
                let markerBounds = CGRect(
                    x: marker.x - markerRadius,
                    y: marker.y - markerRadius,
                    width: markerRadius * 2,
                    height: markerRadius * 2
                )
                context.fill(Path(ellipseIn: markerBounds), with: .color(tint.opacity(0.18)))
                context.stroke(Path(ellipseIn: markerBounds), with: .color(tint), lineWidth: 2)
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

private extension SystemMonitorChartView.Scale {
    func maximum(for points: [Double]) -> Double {
        switch self {
        case .unitInterval:
            1
        case .adaptive:
            max(points.max() ?? 0, 1)
        }
    }
}
