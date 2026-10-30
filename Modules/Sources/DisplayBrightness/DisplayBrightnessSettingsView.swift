#if os(macOS)
import ComposableArchitecture
import Extensions
import SwiftUI

/// Insert into the existing Display form so automatic dimming keeps its current controls.
public struct DisplayBrightnessSettingsView: View {
    @Bindable private var store: StoreOf<DisplayBrightnessFeature>
    @State private var hostID = UUID()

    public init(store: StoreOf<DisplayBrightnessFeature>) { self.store = store }

    public var body: some View {
        Section {
            setting("Enable smooth brightness transitions", detail: "Brightness changes gradually instead of jumping.", keyPath: \.smoothTransitions)
            setting("Combine hardware and software dimming", detail: "Dim below the display’s minimum hardware brightness.", keyPath: \.combinedDimming)
            setting("Sync brightness from built-in and Apple displays", detail: "Native brightness changes are mirrored to external displays.", keyPath: \.syncNativeBrightness)
            setting("Allow zero software brightness", detail: "This can make a display completely black. Use Reset software dimming to restore visibility.", keyPath: \.allowZeroSoftwareBrightness)
            setting("Use keyboard brightness keys", detail: "Use Shift+Option for smaller brightness adjustments.", keyPath: \.controlWithBrightnessKeys)
            if store.settings.controlWithBrightnessKeys {
                switch store.snapshot.brightnessKeyStatus {
                case .needsAccessibility:
                    Label("Allow Accessibility access to use the brightness keys.".localized(), systemImage: "hand.raised")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open System Settings".localized()) { store.send(.requestKeyboardAccess) }
                case .unavailable:
                    Label("Brightness key capture is unavailable. Try enabling it again.".localized(), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                case .inactive, .ready:
                    EmptyView()
                }
            }
            Button("Reset software dimming".localized()) { store.send(.resetSoftwareDimming) }
            if store.settingsSaveFailed {
                Label("Could not save display settings.".localized(), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Brightness".localized())
        }
        .onAppear { store.send(.appeared(hostID: hostID)) }
        .onDisappear { store.send(.disappeared(hostID: hostID)) }
    }

    private func setting(_ title: String, detail: String, keyPath: WritableKeyPath<BrightnessSettings, Bool>) -> some View {
        Toggle(isOn: Binding(get: { store.settings[keyPath: keyPath] }, set: { value in
            var settings = store.settings
            settings[keyPath: keyPath] = value
            store.send(.settingsChanged(settings))
        })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.localized())
                Text(detail.localized()).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
