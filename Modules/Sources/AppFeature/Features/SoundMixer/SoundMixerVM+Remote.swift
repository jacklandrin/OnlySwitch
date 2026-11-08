//
//  SoundMixerVM+Remote.swift
//  OnlySwitch
//

import ComposableArchitecture
import RemoteCore
import Foundation

extension SoundMixerVM {
    /// The remote representation intentionally excludes Core Audio and scripting handles.
    func remoteSnapshot() async -> RemoteSoundMixerSnapshot {
        if enabled { await refresh() }
        return SoundMixerRemoteBridge.snapshot(
            revision: UInt64(Date().timeIntervalSince1970 * 1_000),
            isEnabled: enabled,
            systemVolume: systemVolume,
            isSystemVolumeAvailable: isSystemVolumeAvailable,
            output: outputDevice.map { .init(name: $0.name, symbolName: $0.symbolName) },
            rows: rows.map { .init(id: $0.id, name: $0.name, volume: $0.volume, isMuted: $0.isMuted) },
            equalizer: equalizerStore.withState { $0 },
            routing: outputRoutingStore.withState { $0 }
        )
    }

    func performRemoteCommand(_ command: RemoteSoundMixerCommand) async throws -> RemoteSoundMixerSnapshot {
        guard enabled else { return await remoteSnapshot() }
        let validated = try SoundMixerRemoteBridge.validate(
            command,
            rowIDs: Set(rows.map(\.id)),
            routing: outputRoutingStore.withState { $0 }
        )
        switch validated {
        case let .systemVolume(value):
            updateSystemVolume(value, live: false)
        case let .appVolume(id, value):
            updateVolume(value, for: id, live: false)
        case let .appMuted(id, isMuted):
            if rows.first(where: { $0.id == id })?.isMuted != isMuted { toggleMute(for: id) }
        case let .equalizerGain(id, band, gain):
            equalizerStore.send(.setGain(id, band, gain))
        case let .equalizerReset(id):
            equalizerStore.send(.reset(id))
        case let .toggleOutput(id, deviceID):
            outputRoutingStore.send(.toggleDevice(id, deviceID))
        case let .followSystem(id):
            outputRoutingStore.send(.followSystem(id))
        }
        return await remoteSnapshot()
    }

    /// Polls while a remote Sound Mixer tab is subscribed and emits only snapshots whose content
    /// changed. Cancelling the consumer cancels the polling task.
    func remoteSnapshots(interval: Duration = .seconds(2)) -> AsyncThrowingStream<RemoteSoundMixerSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                var last: RemoteSoundMixerSnapshot?
                // `guard let self` per iteration so the loop ends once the view model is gone.
                while !Task.isCancelled {
                    guard let self else { break }
                    let next = await self.remoteSnapshot()
                    if last.map({ !$0.hasSameContent(as: next) }) ?? true {
                        continuation.yield(next)
                        last = next
                    }
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
