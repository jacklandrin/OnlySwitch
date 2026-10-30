#if os(macOS)
import ComposableArchitecture
import Extensions
import SwiftUI

public struct DisplayBrightnessView: View {
    @Bindable private var store: StoreOf<DisplayBrightnessFeature>
    @State private var hostID = UUID()
    private let compact: Bool
    private let managesScrolling: Bool

    public init(store: StoreOf<DisplayBrightnessFeature>, compact: Bool = false, managesScrolling: Bool = true) {
        self.store = store
        self.compact = compact
        self.managesScrolling = managesScrolling
    }

    public var body: some View {
        Group {
            if managesScrolling { ScrollView { content } }
            else { content }
        }
        .onAppear { store.send(.appeared(hostID: hostID)) }
        .onDisappear { store.send(.disappeared(hostID: hostID)) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HStack {
                Label("Brightness".localized(), systemImage: "sun.max.fill")
                    .font(compact ? .headline : .title2.bold())
                Spacer(minLength: 8)
                if store.isRefreshing { ProgressView().controlSize(.small) }
                Button("Refresh".localized(), systemImage: "arrow.clockwise") { store.send(.refresh) }
                    .labelStyle(.iconOnly)
                    .disabled(store.isRefreshing)
            }
            if store.settings.controlWithBrightnessKeys {
                if store.snapshot.brightnessKeyStatus == .needsAccessibility {
                    warning("Allow Accessibility access to use the brightness keys.")
                    Button("Open System Settings".localized()) { store.send(.requestKeyboardAccess) }
                        .buttonStyle(.link)
                } else if store.snapshot.brightnessKeyStatus == .unavailable {
                    warning("Brightness key capture is unavailable. Try enabling it again.")
                }
            }
            if store.refreshFailed {
                warning("Could not refresh displays.")
            }
            if store.snapshot.displays.isEmpty, !store.isRefreshing {
                ContentUnavailableView("No displays found".localized(), systemImage: "display")
            }
            ForEach(store.snapshot.displays) { display in
                row(display)
            }
            Button("Reset software dimming".localized()) { store.send(.resetSoftwareDimming) }
                .buttonStyle(.link)
        }
        .padding(compact ? 15 : 24)
        .frame(maxWidth: 700, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ display: BrightnessDisplay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "display").foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(controlTitle(display.control).localized()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(display.level, format: .percent.precision(.fractionLength(0)))
                    .font(.body.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { store.snapshot.displays.first(where: { $0.id == display.id })?.level ?? display.level },
                set: { store.send(.levelChanged(screenID: display.id, level: $0)) }
            ), in: 0...1) {
                Text(display.name)
            } minimumValueLabel: {
                Image(systemName: "sun.min").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "sun.max.fill").accessibilityHidden(true)
            }
            .disabled(display.control == .unavailable)
            .accessibilityLabel(display.name + ", " + "Brightness".localized())
            .accessibilityValue(Text(display.level, format: .percent.precision(.fractionLength(0))))
            if display.error { warning("Could not update brightness. Try refreshing.") }
        }
        .padding(compact ? 12 : 16)
        .modifier(BrightnessSurface())
    }

    private func warning(_ key: String) -> some View {
        Label(key.localized(), systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func controlTitle(_ control: BrightnessControl) -> String {
        switch control {
        case .native, .ddc: "Hardware brightness"
        case .software: "Software dimming"
        case .unavailable: "Brightness unavailable"
        }
    }
}

private struct BrightnessSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
        }
    }
}
#endif
