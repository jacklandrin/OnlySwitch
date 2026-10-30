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
        nowPlaying: { source in
            switch source {
            case .appleMusic:
                guard let player = AppleMusicSwitch.shared.player else { return nil }
                return track(
                    bundleID: appleMusicBundleID,
                    notified: player.notifiedTrack,
                    current: {
                        let track = player.applemusicApp.currentTrack
                        return (track?.name, track?.artist)
                    }
                )
            case .spotify:
                guard let player = SpotifySwitch.shared.player else { return nil }
                return track(
                    bundleID: spotifyBundleID,
                    notified: player.notifiedTrack,
                    current: {
                        let track = player.spotifyApp.currentTrack
                        return (track?.name, track?.artist)
                    }
                )
            case .radio:
                guard Preferences.shared.radioEnable else { return nil }
                let item = RadioStationSwitch.shared.playerItem
                return .radio(stationName: item.title, streamInfo: item.streamInfo)
            }
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
        guard let canAutomate = canAutomate(bundleID: bundleID) else { return nil }
        switch canAutomate ? currentState() : cachedState {
        case .playing, .fastForwarding, .rewinding, .reposition:
            return .playing
        case .paused:
            return .paused
        case .stopped:
            return nil
        }
    }

    @MainActor
    private static func track(
        bundleID: String,
        notified: (name: String?, artist: String?)?,
        current: () -> (name: String?, artist: String?)
    ) -> DesktopPetNowPlaying? {
        guard let canAutomate = canAutomate(bundleID: bundleID) else { return nil }
        let nowPlaying = { (track: (name: String?, artist: String?)?) in
            track.flatMap { DesktopPetNowPlaying.track(name: $0.name, artist: $0.artist) }
        }
        // Players can briefly report an empty current track, e.g. while changing tracks.
        return (canAutomate ? nowPlaying(current()) : nil) ?? nowPlaying(notified)
    }

    /// `nil` when the player is not running. Never prompts for Automation permission.
    @MainActor
    private static func canAutomate(bundleID: String) -> Bool? {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first else { return nil }
        let target = NSAppleEventDescriptor(processIdentifier: application.processIdentifier)
        return AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, false
        ) == noErr
    }
}
