import AppKit
import ApplicationServices
import DesktopPet

extension DesktopPetPlaybackClient {
    static let appLive = Self(
        playingSources: {
            var sources: Set<DesktopPetPlaybackSource> = []
            if let player = AppleMusicSwitch.shared.player,
               isPlaying(
                   bundleID: "com.apple.Music",
                   cachedState: AppleMusicSwitch.shared.state,
                   currentState: { player.playbackState }
               ) {
                sources.insert(.appleMusic)
            }
            if let player = SpotifySwitch.shared.player,
               isPlaying(
                   bundleID: "com.spotify.client",
                   cachedState: SpotifySwitch.shared.state,
                   currentState: { player.playbackState }
               ) {
                sources.insert(.spotify)
            }
            if Preferences.shared.radioEnable,
               RadioStationSwitch.shared.playerItem.isPlaying {
                sources.insert(.radio)
            }
            return sources
        },
        next: { source in
            switch source {
            case .appleMusic:
                AppleMusicSwitch.shared.player?.nextTrack()
            case .spotify:
                SpotifySwitch.shared.player?.nextTrack()
            case .radio:
                let item = RadioStationSwitch.shared.playerItem
                guard Preferences.shared.radioEnable, item.isPlaying else { return }
                item.nextStation()
            }
        }
    )

    /// Polling must never launch a player or ask for Automation permission.
    /// Distributed playback notifications remain usable before permission is granted.
    @MainActor
    private static func isPlaying(
        bundleID: String,
        cachedState: MusicPlaybackState,
        currentState: () -> MusicPlaybackState
    ) -> Bool {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first else { return false }
        let target = NSAppleEventDescriptor(processIdentifier: application.processIdentifier)
        let permission = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, false
        )
        return (permission == noErr ? currentState() : cachedState) == .playing
    }
}
