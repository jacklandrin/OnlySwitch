import AppKit
import ApplicationServices
import DesktopPet

extension DesktopPetPlaybackClient {
    static let appLive = Self(
        statuses: {
            var statuses: [DesktopPetPlaybackSource: DesktopPetPlaybackStatus] = [:]
            if let player = AppleMusicSwitch.shared.player {
                statuses[.appleMusic] = status(
                    bundleID: appleMusicBundleID,
                    cachedState: AppleMusicSwitch.shared.state,
                    currentState: { player.playbackState }
                )
            }
            if let player = SpotifySwitch.shared.player {
                statuses[.spotify] = status(
                    bundleID: spotifyBundleID,
                    cachedState: SpotifySwitch.shared.state,
                    currentState: { player.playbackState }
                )
            }
            if Preferences.shared.radioEnable,
               RadioStationSwitch.shared.playerItem.isPlaying {
                statuses[.radio] = .playing
            }
            return statuses
        },
        next: { source in
            switch source {
            case .appleMusic:
                guard isRunning(bundleID: appleMusicBundleID) else { return }
                AppleMusicSwitch.shared.player?.nextTrack()
            case .spotify:
                guard isRunning(bundleID: spotifyBundleID) else { return }
                SpotifySwitch.shared.player?.nextTrack()
            case .radio:
                guard Preferences.shared.radioEnable else { return }
                RadioStationSwitch.shared.playerItem.nextStation()
            }
        },
        play: { source in
            switch source {
            case .appleMusic:
                guard isRunning(bundleID: appleMusicBundleID) else { return }
                _ = AppleMusicSwitch.shared.player?.play()
            case .spotify:
                guard isRunning(bundleID: spotifyBundleID) else { return }
                _ = SpotifySwitch.shared.player?.play()
            case .radio:
                guard Preferences.shared.radioEnable else { return }
                RadioStationSwitch.shared.playerItem.isPlaying = true
            }
        },
        pause: { source in
            switch source {
            case .appleMusic:
                guard isRunning(bundleID: appleMusicBundleID) else { return }
                _ = AppleMusicSwitch.shared.player?.pause()
            case .spotify:
                guard isRunning(bundleID: spotifyBundleID) else { return }
                _ = SpotifySwitch.shared.player?.pause()
            case .radio:
                RadioStationSwitch.shared.playerItem.isPlaying = false
            }
        }
    )

    private static let appleMusicBundleID = "com.apple.Music"
    private static let spotifyBundleID = "com.spotify.client"

    /// Commands must never launch a player that was quit after the controls appeared.
    @MainActor
    private static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Polling must never launch a player or ask for Automation permission.
    /// Distributed playback notifications remain usable before permission is granted.
    @MainActor
    private static func status(
        bundleID: String,
        cachedState: MusicPlaybackState,
        currentState: () -> MusicPlaybackState
    ) -> DesktopPetPlaybackStatus? {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first else { return nil }
        let target = NSAppleEventDescriptor(processIdentifier: application.processIdentifier)
        let permission = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, false
        )
        switch permission == noErr ? currentState() : cachedState {
        case .playing, .fastForwarding, .rewinding, .reposition:
            return .playing
        case .paused:
            return .paused
        case .stopped:
            return nil
        }
    }
}
