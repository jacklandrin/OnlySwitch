//
//  SoundMixerRemoteBridge.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/10/30.
//

import RemoteCore
import SoundMixerEQ

/// Pure mapping between the Mac mixer state and the remote wire contract. It never sees PIDs,
/// Core Audio object IDs, or tap handles, so none of them can reach the wire.
enum SoundMixerRemoteBridge {
    struct Row: Equatable {
        var id: String
        var name: String
        var volume: Double
        var isMuted: Bool
    }

    /// A remote command after it was checked against the current Mac state and clamped.
    enum Validated: Equatable {
        case systemVolume(Double)
        case appVolume(String, Double)
        case appMuted(String, Bool)
        case equalizerGain(String, Int, Double)
        case equalizerReset(String)
        case toggleOutput(String, String)
        case followSystem(String)
    }

    static func snapshot(
        revision: UInt64,
        isEnabled: Bool,
        systemVolume: Double,
        isSystemVolumeAvailable: Bool,
        output: RemoteSoundMixerOutput?,
        rows: [Row],
        equalizer: EqualizerFeature.State,
        routing: OutputRoutingFeature.State
    ) -> RemoteSoundMixerSnapshot {
        guard isEnabled else {
            return RemoteSoundMixerSnapshot(
                revision: revision, isEnabled: false, systemVolume: systemVolume, output: output, apps: [],
                isSystemVolumeAvailable: isSystemVolumeAvailable
            )
        }
        let apps = rows.map { row in
            RemoteSoundMixerApp(
                id: row.id,
                name: row.name,
                volume: row.volume,
                isMuted: row.isMuted,
                equalizer: equalizer.apps[row.id].map {
                    RemoteSoundMixerEqualizer(gains: $0.settings.gains, status: .init(status: $0.status))
                },
                routing: routing.apps[row.id].map {
                    RemoteSoundMixerRouting(selectedDeviceIDs: $0.selection.deviceUIDs, status: .init(status: $0.status))
                }
            )
        }
        return RemoteSoundMixerSnapshot(
            revision: revision, isEnabled: true, systemVolume: systemVolume, output: output, apps: apps,
            isSystemVolumeAvailable: isSystemVolumeAvailable,
            outputDevices: routing.devices.map { .init(id: $0.id, name: $0.name, isDefault: $0.isDefault) }
        )
    }

    static func validate(
        _ command: RemoteSoundMixerCommand,
        rowIDs: Set<String>,
        routing: OutputRoutingFeature.State
    ) throws(RemoteProtocolError) -> Validated {
        func row(_ id: String) throws(RemoteProtocolError) -> String {
            guard rowIDs.contains(id) else {
                throw RemoteProtocolError(code: .controlNotFound, message: "Sound source is no longer available")
            }
            return id
        }
        // EQ and routing need a process tap; rows without one (OnlySwitch's own player) have no state here.
        func processingRow(_ id: String) throws(RemoteProtocolError) -> String {
            let id = try row(id)
            guard routing.apps[id] != nil else {
                throw RemoteProtocolError(code: .actionNotSupported, message: "This sound source has no equalizer or routing")
            }
            return id
        }
        switch command {
        case let .setSystemVolume(value):
            return .systemVolume(RemoteSoundMixerApp.clampVolume(value))
        case let .setAppVolume(id, value):
            return .appVolume(try row(id), RemoteSoundMixerApp.clampVolume(value))
        case let .setAppMuted(id, isMuted):
            return .appMuted(try row(id), isMuted)
        case let .setAppEqualizerGain(id, band, gain):
            guard (0..<RemoteSoundMixerEqualizer.bandCount).contains(band) else {
                throw RemoteProtocolError(code: .actionNotSupported, message: "Unknown equalizer band")
            }
            return .equalizerGain(try processingRow(id), band, RemoteSoundMixerEqualizer.clampGain(gain))
        case let .resetAppEqualizer(id):
            return .equalizerReset(try processingRow(id))
        case let .toggleAppOutputDevice(id, deviceID):
            let id = try processingRow(id)
            // An unplugged device stays deselectable; only a new selection must be online.
            let isSelected = routing.selection(for: id).deviceUIDs.contains(deviceID)
            guard isSelected || routing.devices.contains(where: { $0.id == deviceID }) else {
                throw RemoteProtocolError(code: .controlNotFound, message: "Output device is no longer available")
            }
            return .toggleOutput(id, deviceID)
        case let .followSystemOutput(id):
            return .followSystem(try processingRow(id))
        }
    }
}

private extension RemoteSoundMixerEqualizer.Status {
    init(status: EqualizerFeature.Status) {
        switch status {
        case .flat: self = .flat
        case .pending: self = .pending
        case .waitingForAudio: self = .waitingForAudio
        case .active: self = .active
        case .unavailable: self = .unavailable
        case .unsupported: self = .unsupported
        }
    }
}

private extension RemoteSoundMixerRouting.Status {
    init(status: OutputRoutingFeature.Status) {
        switch status {
        case .followingSystem: self = .followingSystem
        case .pending: self = .pending
        case .waitingForDevices: self = .waitingForDevices
        case .partial: self = .partial
        case .active: self = .active
        case .unsupported: self = .unsupported
        case .unavailable: self = .unavailable
        }
    }
}
