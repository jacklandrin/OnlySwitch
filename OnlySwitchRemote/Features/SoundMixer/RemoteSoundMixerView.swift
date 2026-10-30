import ComposableArchitecture
import RemoteCore
import SwiftUI

struct RemoteSoundMixerView: View {
    let store: StoreOf<RemoteSoundMixerFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if store.selectedMacID == nil {
                ContentUnavailableView(
                    "No Mac Selected",
                    systemImage: "desktopcomputer",
                    description: Text("Select a paired Mac from the navigation bar.")
                )
            } else if store.connectionState != .authenticated {
                ContentUnavailableView(
                    "Sound Mixer",
                    systemImage: "wifi.slash",
                    description: Text("The selected Mac is offline.")
                )
            } else if let message = store.availabilityMessage {
                ContentUnavailableView(
                    "Sound Mixer",
                    systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: message)
                )
            } else if let snapshot = store.snapshot {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if snapshot.isEnabled {
                            systemCard(snapshot)
                            if snapshot.apps.isEmpty {
                                RemoteUnavailableCard(message: "No controllable apps are running")
                            }
                            ForEach(snapshot.apps) { app in
                                appCard(app, devices: snapshot.outputDevices)
                            }
                        } else {
                            RemoteUnavailableCard(message: "Sound Mixer is off on this Mac. Turn it on from Controls.")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, RemotePageTabBar.contentBottomInset + 16)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Sound Mixer")
    }

    private func systemCard(_ snapshot: RemoteSoundMixerSnapshot) -> some View {
        let systemKey = RemoteSoundMixerFeature.systemKey
        return RemoteSystemMonitorCardSurface {
            VStack(alignment: .leading, spacing: 12) {
                RemoteMixerSlider(
                    label: String(localized: "System Volume"),
                    value: store.state.volume(for: systemKey) ?? snapshot.systemVolume,
                    isEnabled: store.canSendCommands && snapshot.isSystemVolumeAvailable,
                    onChange: { store.send(.volumeChanged(target: systemKey, value: $0)) },
                    onEditingChanged: { if $0 == false { store.send(.volumeCommitted(target: systemKey)) } }
                )
                if let output = snapshot.output {
                    Label {
                        Text(verbatim: output.name)
                    } icon: {
                        Image(systemName: output.symbolName)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if snapshot.isSystemVolumeAvailable == false {
                    Text("This output device doesn't support volume control")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let commandError = store.commandError {
                    Label {
                        Text(verbatim: commandError)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private func speakerSymbol(isMuted: Bool, volume: Double) -> String {
        if isMuted { return "speaker.slash.fill" }
        if volume <= 0 { return "speaker.fill" }
        if volume < 34 { return "speaker.wave.1.fill" }
        if volume < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func appCard(_ app: RemoteSoundMixerApp, devices: [RemoteSoundMixerOutputDevice]) -> some View {
        let isExpanded = store.expandedAppIDs.contains(app.id)
        let volume = store.state.volume(for: app.id) ?? app.volume
        return RemoteSystemMonitorCardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    RemoteMixerSlider(
                        label: app.name,
                        value: volume,
                        isEnabled: store.canSendCommands,
                        onChange: { store.send(.volumeChanged(target: app.id, value: $0)) },
                        onEditingChanged: { if $0 == false { store.send(.volumeCommitted(target: app.id)) } }
                    )
                    Button(
                        app.isMuted ? "Unmute" : "Mute",
                        systemImage: speakerSymbol(isMuted: app.isMuted, volume: volume)
                    ) {
                        store.send(.muteToggled(appID: app.id))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(store.canSendCommands == false)
                }
                if app.equalizer != nil || app.routing != nil {
                    Button {
                        store.send(.expandedToggled(appID: app.id), animation: reduceMotion ? nil : .snappy)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Output & Equalizer")
                                if let routing = app.routing {
                                    outputSummary(routing, devices: devices)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
                    if isExpanded {
                        expandedSection(app, devices: devices)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: app.name))
    }

    private func expandedSection(_ app: RemoteSoundMixerApp, devices: [RemoteSoundMixerOutputDevice]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let routing = app.routing {
                RemoteOutputDevicePicker(
                    routing: routing,
                    devices: devices,
                    commandError: store.commandError,
                    onFollowSystem: { store.send(.followSystemOutput(appID: app.id)) },
                    onToggleDevice: { store.send(.outputDeviceToggled(appID: app.id, deviceID: $0)) }
                )
                .disabled(store.canSendCommands == false || routing.status == .unsupported)
                if let message = routingStatusMessage(routing.status) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let equalizer = app.equalizer {
                if app.routing != nil { Divider() }
                RemoteEqualizerView(
                    equalizer: equalizer,
                    isEnabled: store.canSendCommands,
                    gain: { store.state.gain(appID: app.id, band: $0) },
                    onGainChange: { store.send(.gainChanged(appID: app.id, band: $0, gain: $1)) },
                    onGainCommit: { store.send(.gainCommitted(appID: app.id, band: $0)) },
                    onReset: { store.send(.equalizerReset(appID: app.id)) }
                )
            }
        }
    }

    private func outputSummary(
        _ routing: RemoteSoundMixerRouting,
        devices: [RemoteSoundMixerOutputDevice]
    ) -> Text {
        if routing.selectedDeviceIDs.isEmpty {
            let name = devices.first(where: \.isDefault)?.name
            return Text(verbatim: String(localized: "Follow System Output") + (name.map { " · \($0)" } ?? ""))
        }
        let names = routing.selectedDeviceIDs.map { id in
            devices.first(where: { $0.id == id })?.name ?? String(localized: "Unavailable output device")
        }
        return Text(verbatim: names.joined(separator: " · "))
    }

    private func routingStatusMessage(_ status: RemoteSoundMixerRouting.Status) -> LocalizedStringKey? {
        switch status {
        case .waitingForDevices, .partial: "Some selected output devices are disconnected"
        case .unavailable: "Unable to route audio to the selected output devices."
        case .unsupported: "Not supported for this app"
        case .followingSystem, .pending, .active: nil
        }
    }
}

private struct RemoteUnavailableCard: View {
    let message: LocalizedStringKey

    var body: some View {
        RemoteSystemMonitorCardSurface {
            Label(message, systemImage: "speaker.slash")
                .foregroundStyle(.secondary)
        }
    }
}

/// Presentation-only mode lets users browse devices before selecting the first one.
/// An empty confirmed selection continues to mean "follow system" on the Mac.
private struct RemoteOutputDevicePicker: View {
    let routing: RemoteSoundMixerRouting
    let devices: [RemoteSoundMixerOutputDevice]
    let commandError: String?
    let onFollowSystem: () -> Void
    let onToggleDevice: (String) -> Void
    @State private var isChoosingDevices: Bool?

    private var showsDevices: Bool { isChoosingDevices ?? (routing.selectedDeviceIDs.isEmpty == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Output Devices")
                .font(.subheadline.weight(.semibold))
            Picker("Output Devices", selection: Binding(
                get: { showsDevices },
                set: { choosing in
                    isChoosingDevices = choosing
                    if choosing == false { onFollowSystem() }
                }
            )) {
                Text("Follow System").tag(false)
                Text("Choose Devices").tag(true)
            }
            .pickerStyle(.segmented)

            if showsDevices {
                Text("Select up to 16 output devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(devices) { device in
                        deviceRow(
                            id: device.id,
                            title: Text(verbatim: device.name),
                            caption: device.isDefault ? Text("System Output") : nil
                        )
                    }
                    let knownIDs = Set(devices.map(\.id))
                    ForEach(routing.selectedDeviceIDs.filter { knownIDs.contains($0) == false }, id: \.self) { id in
                        deviceRow(id: id, title: Text("Unavailable output device"), caption: nil)
                    }
                }
            } else if let device = devices.first(where: \.isDefault) {
                Label {
                    Text(verbatim: device.name)
                } icon: {
                    Image(systemName: "speaker.wave.2")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: routing.selectedDeviceIDs) { _, _ in
            isChoosingDevices = nil
        }
        .onChange(of: commandError) { _, error in
            if error != nil { isChoosingDevices = nil }
        }
    }

    private func deviceRow(id: String, title: Text, caption: Text?) -> some View {
        let selected = routing.selectedDeviceIDs.contains(id)
        return Button { onToggleDevice(id) } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if let caption {
                        caption.font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(selected == false && routing.selectedDeviceIDs.count >= 16)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
