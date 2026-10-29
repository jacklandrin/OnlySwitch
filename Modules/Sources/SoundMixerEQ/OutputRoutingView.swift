#if os(macOS)
import ComposableArchitecture
import SwiftUI

/// This control changes only this App's routing. It never changes the system default output.
public struct OutputRoutingView: View {
    @Bindable private var store: StoreOf<OutputRoutingFeature>
    private let appID: String
    private let appName: String
    private let localize: (String) -> String
    @State private var isExpanded = false
    public init(store: StoreOf<OutputRoutingFeature>, appID: String, appName: String,
                localize: @escaping (String) -> String = { $0 }) {
        self.store = store; self.appID = appID; self.appName = appName; self.localize = localize
    }
    public var body: some View {
        if let app = store.apps[appID] {
            VStack(alignment: .leading, spacing: 3) {
                Button { isExpanded.toggle() } label: {
                    HStack(spacing: 5) {
                        Label(localize("Output Devices"), systemImage: "hifispeaker.2.fill")
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(!app.source.isSupported)
                .accessibilityLabel(Text(String(format: localize("Output devices for %@"), appName)))
                .accessibilityValue(Text(localize(isExpanded ? "Expanded" : "Collapsed")))
                if isExpanded { outputChoices(app) }
                if let message = message(app.status) {
                    Text(localize(message)).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func outputChoices(_ app: OutputRoutingFeature.App) -> some View {
        let online = Set(store.devices.map(\.id))
        let missing = app.selection.deviceUIDs.filter { !online.contains($0) }
        return VStack(alignment: .leading, spacing: 10) {
            Button { store.send(.followSystem(appID)) } label: {
                Label(localize("Follow System Output"), systemImage: app.selection.followsSystem ? "checkmark" : "speaker.wave.2")
            }
            .buttonStyle(.plain)
            Divider()
            ForEach(store.devices) { device in
                deviceToggle(uid: device.id, name: device.name, selection: app.selection)
            }
            ForEach(missing, id: \.self) { uid in
                deviceToggle(uid: uid, name: store.knownDevices[uid]?.name ?? localize("Unavailable output device"),
                             selection: app.selection)
            }
            Text(localize("Select up to 16 output devices")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func deviceToggle(uid: String, name: String, selection: OutputRouteSelection) -> some View {
        let selected = selection.deviceUIDs.contains(uid)
        return Toggle(name, isOn: Binding(get: { selected }, set: { _ in store.send(.toggleDevice(appID, uid)) }))
            .toggleStyle(.checkbox)
            .lineLimit(1)
            .help(name)
            .disabled(!selected && selection.deviceUIDs.count >= 16)
    }
    private func message(_ status: OutputRoutingFeature.Status) -> String? {
        switch status {
        case .waitingForDevices: "Selected output devices are disconnected. Audio follows the app’s original output until they reconnect."
        case .partial: "Some selected output devices are disconnected"
        case .unsupported: "App audio routing requires macOS 14.4 or later"
        case .unavailable: "Unable to route audio to the selected output devices."
        case .pending: "Waiting for audio. Check audio recording permission if playback is silent."
        case .active, .followingSystem: nil
        }
    }
}
#endif
