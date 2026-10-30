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

    private func appCard(_ app: RemoteSoundMixerApp, devices: [RemoteSoundMixerOutputDevice]) -> some View {
        let isExpanded = store.expandedAppIDs.contains(app.id)
        return RemoteSystemMonitorCardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    RemoteMixerSlider(
                        label: app.name,
                        value: store.state.volume(for: app.id) ?? app.volume,
                        isEnabled: store.canSendCommands,
                        onChange: { store.send(.volumeChanged(target: app.id, value: $0)) },
                        onEditingChanged: { if $0 == false { store.send(.volumeCommitted(target: app.id)) } }
                    )
                    Button(
                        app.isMuted ? "Unmute" : "Mute",
                        systemImage: app.isMuted ? "speaker.slash.fill" : "speaker.fill"
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
                            Text("Output & Equalizer")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output Devices")
                        .font(.subheadline.weight(.semibold))
                    routeRow(
                        title: Text("Follow System Output"),
                        caption: nil,
                        isSelected: routing.selectedDeviceIDs.isEmpty
                    ) {
                        store.send(.followSystemOutput(appID: app.id))
                    }
                    ForEach(devices) { device in
                        routeRow(
                            title: Text(verbatim: device.name),
                            caption: device.isDefault ? Text("System Output") : nil,
                            isSelected: routing.selectedDeviceIDs.contains(device.id)
                        ) {
                            store.send(.outputDeviceToggled(appID: app.id, deviceID: device.id))
                        }
                    }
                    let knownIDs = Set(devices.map(\.id))
                    ForEach(routing.selectedDeviceIDs.filter { knownIDs.contains($0) == false }, id: \.self) { deviceID in
                        routeRow(title: Text("Unavailable output device"), caption: nil, isSelected: true) {
                            store.send(.outputDeviceToggled(appID: app.id, deviceID: deviceID))
                        }
                    }
                    if let message = routingStatusMessage(routing.status) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(store.canSendCommands == false || routing.status == .unsupported)
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

    private func routeRow(
        title: Text,
        caption: Text?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if let caption {
                        caption
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
