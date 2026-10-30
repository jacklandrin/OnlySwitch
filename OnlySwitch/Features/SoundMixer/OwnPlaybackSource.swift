//
//  OwnPlaybackSource.swift
//  OnlySwitch
//

import AppKit

/// OnlySwitch's own radio and background-noise playback. It can't go through a process tap:
/// every tapped app's processed audio is played from this process, so tapping ourselves would
/// feed that audio back into the mixer. The player's own volume is used instead.
@MainActor
struct OwnPlaybackSource {
    static let rowID = "onlyswitch.own-playback"

    var isPlaying: () -> Bool
    /// 0...100
    var volume: () -> Double
    var setVolume: (Double) -> Void

    static let live = OwnPlaybackSource(
        isPlaying: { PlayerManager.shared.player.currentPlayerItem?.isPlaying == true },
        volume: { Double(Preferences.shared.volume) * 100 },
        setVolume: { Preferences.shared.volume = Float(min(100, max(0, $0)) / 100) }
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
