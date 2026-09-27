import RemoteCore
import SwiftUI

struct RemoteSystemMonitorGaugePresentation: Equatable {
    let title: String
    let usage: Double?

    init(title: String, usage: MetricAvailability<Double>) {
        self.title = title
        if case let .available(value) = usage, value.isFinite {
            self.usage = min(max(value, 0), 1)
        } else {
            self.usage = nil
        }
    }

    var accessibilityLabel: String { "\(title) usage" }

    var accessibilityValue: String {
        guard let usage else { return String(localized: "Unavailable") }
        return "\(Int((usage * 100).rounded()))%"
    }

    var displayValue: String { accessibilityValue }
}

enum RemoteSystemMonitorGaugeAccent: Equatable {
    case cpu
    case gpu
    case memory

    init(metric: SystemMonitorMetric) {
        switch metric {
        case .cpu: self = .cpu
        case .gpu: self = .gpu
        case .memory: self = .memory
        case .disk, .network: self = .cpu
        }
    }

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .cpu: colors = [.cyan, .blue, .indigo]
        case .gpu: colors = [.purple, .pink, .orange]
        case .memory: colors = [.mint, .teal, .blue]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

struct RemoteSystemMonitorGaugeView: View {
    let presentation: RemoteSystemMonitorGaugePresentation
    let symbol: String
    let accent: RemoteSystemMonitorGaugeAccent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var trackWidth = 22.0
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = 60.0

    var body: some View {
        VStack(spacing: 8) {
            Label(LocalizedStringKey(presentation.title), systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { proxy in
                let center = CGPoint(
                    x: proxy.size.width / 2,
                    y: proxy.size.height - trackWidth - 8
                )
                let radius = max(
                    0,
                    min(proxy.size.width / 2 - trackWidth, center.y - trackWidth)
                )

                ZStack {
                    gaugeArc(center: center, radius: radius, endAngle: 0)
                        .stroke(
                            Color.primary.opacity(0.22),
                            style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                        )

                    if let usage = presentation.usage {
                        if differentiateWithoutColor == false && contrast != .increased {
                            gaugeArc(center: center, radius: radius, endAngle: 180 + (usage * 180))
                                .stroke(
                                    accent.gradient,
                                    style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                                )
                                .opacity(0.24)
                                .blur(radius: 5)
                        }

                        gaugeArc(center: center, radius: radius, endAngle: 180 + (usage * 180))
                            .stroke(
                                accent.gradient,
                                style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
                            )

                        if differentiateWithoutColor || contrast == .increased {
                            gaugeArc(center: center, radius: radius, endAngle: 180 + (usage * 180))
                                .stroke(
                                    Color.primary.opacity(0.55),
                                    style: StrokeStyle(
                                        lineWidth: 2,
                                        lineCap: .round,
                                        dash: [5, 5]
                                    )
                                )
                        }
                    }

                    Text(verbatim: presentation.displayValue)
                        .font(.system(size: valueSize, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .foregroundStyle(presentation.usage == nil ? .secondary : .primary)
                        .position(x: center.x, y: max(center.y - radius * 0.18, valueSize / 2))
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: presentation.usage)
            }
            .aspectRatio(2, contentMode: .fit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
    }

    private func gaugeArc(center: CGPoint, radius: Double, endAngle: Double) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(endAngle),
                clockwise: false
            )
        }
    }

}
