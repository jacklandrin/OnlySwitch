#if os(macOS)
import ComposableArchitecture
import SwiftUI

/// Compact editor; the parent owns the app row and disclosure control.
/// Presets are the primary control; manual band editing sits behind a second-level disclosure.
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
                Text(localize("Equalizer")).font(.caption.weight(.semibold))
                if app.source.isSupported {
                    EqualizerPresetGrid(selected: app.settings.preset, localize: localize) {
                        store.send(.applyPreset(appID, $0))
                    }
                    customSection(app)
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

    @ViewBuilder
    private func customSection(_ app: EqualizerFeature.App) -> some View {
        Button {
            store.send(.toggleCustomExpanded(appID), animation: .snappy(duration: 0.2))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(app.isCustomExpanded ? 90 : 0))
                    .accessibilityHidden(true)
                Text(localize("Custom EQ"))
                Spacer(minLength: 4)
                if app.settings.preset == nil {
                    Text(localize("Custom"))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(localize(app.isCustomExpanded ? "Expanded" : "Collapsed")))
        if app.isCustomExpanded {
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

/// Four-column chip grid; the selected chip mirrors the curve that is currently applied.
struct EqualizerPresetGrid: View {
    let selected: EqualizerPreset?
    let localize: (String) -> String
    let onSelect: (EqualizerPreset) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(EqualizerPreset.allCases) { preset in
                chip(preset)
            }
        }
    }

    private func chip(_ preset: EqualizerPreset) -> some View {
        let isSelected = preset == selected
        return Button { onSelect(preset) } label: {
            Text(localize(preset.titleKey))
                .font(.caption2.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 22)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(localize(preset.titleKey))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
