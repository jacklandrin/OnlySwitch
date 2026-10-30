import SwiftUI

struct RemoteMixerSlider: View {
    static let accessibilityStep = 5.0

    let label: String
    let value: Double
    var isEnabled = true
    var minimumSymbol: String?
    var maximumSymbol: String?
    let onChange: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(verbatim: percentText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                if let minimumSymbol { valueSymbol(minimumSymbol) }
                Slider(
                    value: Binding(get: { value }, set: onChange),
                    in: 0 ... 100,
                    onEditingChanged: onEditingChanged
                )
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityValue(Text(verbatim: percentText))
                .accessibilityAdjustableAction { direction in
                    let delta: Double
                    switch direction {
                    case .increment: delta = Self.accessibilityStep
                    case .decrement: delta = -Self.accessibilityStep
                    @unknown default: return
                    }
                    onChange(min(100, max(0, value + delta)))
                    onEditingChanged(false)
                }
                if let maximumSymbol { valueSymbol(maximumSymbol) }
            }
        }
        .disabled(isEnabled == false)
    }

    private func valueSymbol(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var percentText: String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
