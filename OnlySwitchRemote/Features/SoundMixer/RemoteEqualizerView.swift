import RemoteCore
import SwiftUI

struct RemoteEqualizerView: View {
    static let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    let equalizer: RemoteSoundMixerEqualizer
    var isEnabled = true
    let gain: (Int) -> Double
    let onGainChange: (Int, Double) -> Void
    let onGainCommit: (Int) -> Void
    let onReset: () -> Void
    @ScaledMetric(relativeTo: .body) private var sliderLength: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Equalizer", systemImage: "slider.vertical.3")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Button("Reset EQ", action: onReset)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isInteractive == false)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(0 ..< RemoteSoundMixerEqualizer.bandCount, id: \.self) { band in
                        bandSlider(band)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .disabled(isInteractive == false)
        }
    }

    private var isInteractive: Bool { isEnabled && equalizer.status != .unsupported }

    private var statusMessage: LocalizedStringKey? {
        switch equalizer.status {
        case .waitingForAudio: "EQ will apply when this app plays audio"
        case .unavailable: "Unable to apply EQ. Check audio recording permission in System Settings."
        case .unsupported: "Not supported for this app"
        case .flat, .active, .pending: nil
        }
    }

    private func bandSlider(_ band: Int) -> some View {
        let value = gain(band)
        return VStack(spacing: 6) {
            Slider(
                value: Binding(get: { value }, set: { onGainChange(band, $0) }),
                in: -12 ... 12,
                step: 0.5,
                onEditingChanged: { if $0 == false { onGainCommit(band) } }
            )
            .frame(width: sliderLength)
            .rotationEffect(.degrees(-90))
            .frame(width: 32, height: sliderLength)
            .accessibilityLabel(Text(verbatim: frequencyText(band)))
            .accessibilityValue(Text(verbatim: gainText(value)))
            .accessibilityAdjustableAction { direction in
                let delta: Double
                switch direction {
                case .increment: delta = 1
                case .decrement: delta = -1
                @unknown default: return
                }
                onGainChange(band, RemoteSoundMixerEqualizer.clampGain(value + delta))
                onGainCommit(band)
            }
            Text(verbatim: Self.bandLabels[band])
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(minWidth: 32)
    }

    private func frequencyText(_ band: Int) -> String {
        Measurement(value: RemoteSoundMixerEqualizer.frequencies[band], unit: UnitFrequency.hertz)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0 ... 2))))
    }

    private func gainText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)).sign(strategy: .always(includingZero: false))) + " dB"
    }
}
