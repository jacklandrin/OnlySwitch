import RemoteCore
import SwiftUI

/// Presets first; manual bands sit behind a "Custom EQ" disclosure.
/// Macs older than protocol 1.11 report no preset, so the manual bands are shown directly.
struct RemoteEqualizerView: View {
    static let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    let equalizer: RemoteSoundMixerEqualizer
    var isEnabled = true
    /// `nil` when presets are unsupported; `.some(nil)` for a custom curve.
    let preset: RemoteEqualizerPreset??
    let isCustomExpanded: Bool
    let gain: (Int) -> Double
    let onGainChange: (Int, Double) -> Void
    let onGainCommit: (Int) -> Void
    let onReset: () -> Void
    let onSelectPreset: (RemoteEqualizerPreset) -> Void
    let onToggleCustom: () -> Void
    @ScaledMetric(relativeTo: .body) private var sliderLength: CGFloat = 132
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth: CGFloat = 92
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Equalizer", systemImage: "slider.vertical.3")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if preset == nil {
                    Button("Reset EQ", action: onReset)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isInteractive == false)
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let preset {
                presetGrid(selected: preset)
                    .disabled(isInteractive == false)
                customDisclosure(isCustom: preset == nil)
                if isCustomExpanded {
                    bands
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            } else {
                bands
            }
        }
    }

    private var bands: some View {
        // Spread bands across wide layouts; scroll when the row cannot fit at its minimum spacing.
        ViewThatFits(in: .horizontal) {
            bandRow
            ScrollView(.horizontal) {
                bandRow
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .disabled(isInteractive == false)
    }

    private func presetGrid(selected: RemoteEqualizerPreset?) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: 8)], spacing: 8) {
            ForEach(RemoteEqualizerPreset.allCases) { preset in
                presetChip(preset, isSelected: preset == selected)
            }
        }
    }

    private func presetChip(_ preset: RemoteEqualizerPreset, isSelected: Bool) -> some View {
        Button { onSelectPreset(preset) } label: {
            Text(preset.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func customDisclosure(isCustom: Bool) -> some View {
        Button(action: onToggleCustom) {
            HStack {
                Text("Custom EQ")
                Spacer(minLength: 8)
                if isCustom {
                    Text("Custom")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isCustomExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityValue(isCustomExpanded ? Text("Expanded") : Text("Collapsed"))
    }

    private var bandRow: some View {
        HStack(spacing: 16) {
            ForEach(0 ..< RemoteSoundMixerEqualizer.bandCount, id: \.self) { band in
                bandSlider(band)
                    .frame(minWidth: 44, maxWidth: .infinity)
            }
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
    }

    private func frequencyText(_ band: Int) -> String {
        Measurement(value: RemoteSoundMixerEqualizer.frequencies[band], unit: UnitFrequency.hertz)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0 ... 2))))
    }

    private func gainText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)).sign(strategy: .always(includingZero: false))) + " dB"
    }
}
