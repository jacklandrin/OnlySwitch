#if os(macOS)
import ComposableArchitecture
import SwiftUI

/// Compact editor; the parent owns the app row and disclosure control.
public struct EqualizerView: View {
    @Bindable private var store: StoreOf<EqualizerFeature>
    private let appID: String
    private let localize: (String) -> String

    public init(store: StoreOf<EqualizerFeature>, appID: String, localize: @escaping (String) -> String = { $0 }) {
        self.store = store; self.appID = appID; self.localize = localize
    }

    public var body: some View {
        if let app = store.apps[appID] {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(localize("Equalizer")).font(.caption.weight(.semibold))
                    Spacer()
                    Button(localize("Reset EQ")) { store.send(.reset(appID)) }
                        .font(.caption)
                        .disabled(app.settings.isFlat)
                }
                if app.source.isSupported {
                    Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                        ForEach(0..<5) { row in
                            GridRow {
                                bandControl(row * 2, settings: app.settings)
                                bandControl(row * 2 + 1, settings: app.settings)
                            }
                        }
                    }
                    Text(verbatim: "−12 dB · 0 dB · +12 dB")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let message = statusMessage(app.status) {
                    Text(localize(message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
        }
    }

    private func bandControl(_ band: Int, settings: EqualizerSettings) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text(verbatim: frequencyLabel(band))
                Spacer(minLength: 2)
                Text(verbatim: String(format: "%+.0f dB", settings.gains[band]))
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Slider(value: Binding(get: { store.apps[appID]?.settings.gains[band] ?? 0 },
                                  set: { store.send(.setGain(appID, band, $0)) }), in: -12...12, step: 1)
                .controlSize(.mini)
                .accessibilityLabel(Text(verbatim: "\(frequencyLabel(band)) EQ"))
                .accessibilityValue(Text(verbatim: String(format: "%+.0f dB", settings.gains[band])))
        }
        .frame(maxWidth: .infinity)
    }

    private func frequencyLabel(_ band: Int) -> String {
        let frequency = EqualizerSettings.frequencies[band]
        return frequency >= 1_000 ? String(format: "%g kHz", frequency / 1_000) : String(format: "%g Hz", frequency)
    }

    private func statusMessage(_ status: EqualizerFeature.Status) -> String? {
        switch status {
        case .unsupported: "EQ requires macOS 14.4 or later"
        case .pending: "EQ will apply when this app plays audio"
        case .unavailable: "Unable to apply EQ. Check audio recording permission in System Settings."
        case .waitingForAudio: "Waiting for audio. Check audio recording permission if playback is silent."
        case .flat, .active: nil
        }
    }
}
#endif
