//
//  OwnPlaybackSource.swift
//  OnlySwitch
//

import AppKit

extension Notification.Name {
    static let ownPlaybackStateChanged = Notification.Name("onlyswitch.ownPlaybackStateChanged")
}

/// OnlySwitch's native radio and background-noise playback. Its volume remains upstream of EQ.
@MainActor
struct OwnPlaybackSource {
    static let rowID = "onlyswitch.own-playback"

    var isPlaying: () -> Bool
    /// 0...100
    var volume: () -> Double
    var setVolume: (Double) -> Void
    struct HelperIdentity: Equatable, Sendable {
        let pid: pid_t
        let generation: UUID
    }
    var helperIdentity: () -> HelperIdentity? = { nil }
    var ownsHelper: (HelperIdentity) -> Bool = { _ in false }

    static let live = OwnPlaybackSource(
        isPlaying: { PlayerManager.shared.player.currentPlayerItem?.isPlaying == true },
        volume: { Double(Preferences.shared.volume) * 100 },
        setVolume: { Preferences.shared.volume = Float(min(100, max(0, $0)) / 100) },
        helperIdentity: {
            guard let player = PlayerManager.shared.player as? HostedAudioPlayer,
                  let pid = player.helperProcessIdentifier, let generation = player.helperGeneration else { return nil }
            return HelperIdentity(pid: pid, generation: generation)
        },
        ownsHelper: { identity in
            guard let player = PlayerManager.shared.player as? HostedAudioPlayer else { return false }
            return player.helperGeneration == identity.generation && player.ownsHelperProcess(identity.pid)
        }
    )
}

extension SoundMixerVM {
    static func ownPlaybackRow(isPlaying: Bool, volume: Double, previous: AppRow?, icon: NSImage?) -> AppRow? {
        guard isPlaying else { return nil }
        let volume = min(100, max(0, volume.isFinite ? volume : 0))
        return AppRow(id: OwnPlaybackSource.rowID,
                      name: "OnlySwitch",
                      icon: icon,
                      control: .ownPlayer,
                      volume: volume,
                      isMuted: volume == 0,
                      volumeBeforeMute: volume > 0 ? volume : (previous?.volumeBeforeMute ?? 100))
    }
}
