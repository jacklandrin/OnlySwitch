import AppKit
import ScriptingBridge

// MARK: SpotifyEPlS
@objc public enum SpotifyEPlS : AEKeyword {
    case stopped = 0x6b505353 /* 'kPSS' */
    case playing = 0x6b505350 /* 'kPSP' */
    case paused = 0x6b505370 /* 'kPSp' */
}

// MARK: SpotifyApplication
@objc public protocol SpotifyApplication: SBApplicationProtocol {
    @objc optional var currentTrack: SpotifyTrack { get } // The current playing track.
    @objc optional var soundVolume: Int { get } // The sound output volume (0 = minimum, 100 = maximum)
    @objc optional var playerState: SpotifyEPlS { get } // Is Spotify stopped, paused, or playing?
    @objc optional var playerPosition: Double { get } // The player’s position within the currently playing track in seconds.
    @objc optional var repeatingEnabled: Bool { get } // Is repeating enabled in the current playback context?
    @objc optional var repeating: Bool { get } // Is repeating on or off?
    @objc optional var shufflingEnabled: Bool { get } // Is shuffling enabled in the current playback context?
    @objc optional var shuffling: Bool { get } // Is shuffling on or off?
    @objc optional func nextTrack() // Skip to the next track.
    @objc optional func previousTrack() // Skip to the previous track.
    @objc optional func playpause() // Toggle play/pause.
    @objc optional func pause() // Pause playback.
    @objc optional func play() // Resume playback.
    @objc optional func playTrack(_ x: String!, inContext: String!) // Start playback of a track in the given context.
    @objc optional func setSoundVolume(_ soundVolume: Int) // The sound output volume (0 = minimum, 100 = maximum)
    @objc optional func setPlayerPosition(_ playerPosition: Double) // The player’s position within the currently playing track in seconds.
    @objc optional func setRepeating(_ repeating: Bool) // Is repeating on or off?
    @objc optional func setShuffling(_ shuffling: Bool) // Is shuffling on or off?
    @objc optional var name: String { get } // The name of the application.
    @objc optional var frontmost: Bool { get } // Is this the frontmost (active) application?
    @objc optional var version: String { get } // The version of the application.
}
extension SBApplication: SpotifyApplication {}

// MARK: SpotifyTrack
@objc public protocol SpotifyTrack: SBObjectProtocol {
    @objc optional var artist: String { get } // The artist of the track.
    @objc optional var album: String { get } // The album of the track.
    @objc optional var discNumber: Int { get } // The disc number of the track.
    @objc optional var duration: Int { get } // The length of the track in seconds.
    @objc optional var playedCount: Int { get } // The number of times this track has been played.
    @objc optional var trackNumber: Int { get } // The index of the track in its album.
    @objc optional var starred: Bool { get } // Is the track starred?
    @objc optional var popularity: Int { get } // How popular is this track? 0-100
    @objc optional func id() -> String // The ID of the item.
    @objc optional var name: String { get } // The name of the track.
    @objc optional var artworkUrl: String { get } // The URL of the track%apos;s album cover.
    @objc optional var artwork: NSImage { get } // The property is deprecated and will never be set. Use the 'artwork url' instead.
    @objc optional var albumArtist: String { get } // That album artist of the track.
    @objc optional var spotifyUrl: String { get } // The URL of the track.
    @objc optional func setSpotifyUrl(_ spotifyUrl: String!) // The URL of the track.
}
extension SBObject: SpotifyTrack {}

