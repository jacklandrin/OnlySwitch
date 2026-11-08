import AppKit
import ScriptingBridge

// MARK: iTunesGenericMethods
@objc public protocol iTunesGenericMethods {
    @objc optional func printPrintDialog(_ printDialog: Bool, withProperties: iTunesPrintSettings!, kind: iTunesEKnd, theme: String!) // Print the specified object(s)
    @objc optional func close() // Close an object
    @objc optional func delete() // Delete an element from an object
    @objc optional func duplicateTo(_ to: SBObject!) -> SBObject // Duplicate one or more object(s)
    @objc optional func exists() -> Bool // Verify if an object exists
    @objc optional func `open`() // Open the specified object(s)
    @objc optional func save() // Save the specified object(s)
    @objc optional func playOnce(_ once: Bool) // play the current track or the specified track or file.
    @objc optional func select() // select the specified object(s)
}

// MARK: iTunesPrintSettings
@objc public protocol iTunesPrintSettings: SBObjectProtocol, iTunesGenericMethods {
    @objc optional var copies: Int { get } // the number of copies of a document to be printed
    @objc optional var collating: Bool { get } // Should printed copies be collated?
    @objc optional var startingPage: Int { get } // the first page of the document to be printed
    @objc optional var endingPage: Int { get } // the last page of the document to be printed
    @objc optional var pagesAcross: Int { get } // number of logical pages laid across a physical page
    @objc optional var pagesDown: Int { get } // number of logical pages laid out down a physical page
    @objc optional var errorHandling: iTunesEnum { get } // how errors are handled
    @objc optional var requestedPrintTime: Date { get } // the time at which the desktop printer should print the document
    @objc optional var printerFeatures: [Any] { get } // printer specific options
    @objc optional var faxNumber: String { get } // for fax number
    @objc optional var targetPrinter: String { get } // for target printer
}
extension SBObject: iTunesPrintSettings {}

// MARK: iTunesApplication
@objc public protocol iTunesApplication: SBApplicationProtocol {
    @objc optional func AirPlayDevices() -> SBElementArray
    @objc optional func browserWindows() -> SBElementArray
    @objc optional func encoders() -> SBElementArray
    @objc optional func EQPresets() -> SBElementArray
    @objc optional func EQWindows() -> SBElementArray
    @objc optional func miniplayerWindows() -> SBElementArray
    @objc optional func playlistWindows() -> SBElementArray
    @objc optional func sources() -> SBElementArray
    @objc optional func videoWindows() -> SBElementArray
    @objc optional func visuals() -> SBElementArray
    @objc optional func windows() -> SBElementArray
    @objc optional var AirPlayEnabled: Bool { get } // is AirPlay currently enabled?
    @objc optional var converting: Bool { get } // is a track currently being converted?
    @objc optional var currentAirPlayDevices: [iTunesAirPlayDevice] { get } // the currently selected AirPlay device(s)
    @objc optional var currentEncoder: iTunesEncoder { get } // the currently selected encoder (MP3, AIFF, WAV, etc.)
    @objc optional var currentEQPreset: iTunesEQPreset { get } // the currently selected equalizer preset
    @objc optional var currentPlaylist: iTunesPlaylist { get } // the playlist containing the currently targeted track
    @objc optional var currentStreamTitle: String { get } // the name of the current song in the playing stream (provided by streaming server)
    @objc optional var currentStreamURL: String { get } // the URL of the playing stream or streaming web site (provided by streaming server)
    @objc optional var currentTrack: iTunesTrack { get } // the current targeted track
    @objc optional var currentVisual: iTunesVisual { get } // the currently selected visual plug-in
    @objc optional var EQEnabled: Bool { get } // is the equalizer enabled?
    @objc optional var fixedIndexing: Bool { get } // true if all AppleScript track indices should be independent of the play order of the owning playlist.
    @objc optional var frontmost: Bool { get } // is iTunes the frontmost application?
    @objc optional var fullScreen: Bool { get } // are visuals displayed using the entire screen?
    @objc optional var name: String { get } // the name of the application
    @objc optional var mute: Bool { get } // has the sound output been muted?
    @objc optional var playerPosition: Double { get } // the player’s position within the currently playing track in seconds.
    @objc optional var playerState: iTunesEPlS { get } // is iTunes stopped, paused, or playing?
    @objc optional var selection: SBObject { get } // the selection visible to the user
    @objc optional var shuffleEnabled: Bool { get } // are songs played in random order?
    @objc optional var shuffleMode: iTunesEShM { get } // the playback shuffle mode
    @objc optional var songRepeat: iTunesERpt { get } // the playback repeat mode
    @objc optional var soundVolume: Int { get } // the sound output volume (0 = minimum, 100 = maximum)
    @objc optional var version: String { get } // the version of iTunes
    @objc optional var visualsEnabled: Bool { get } // are visuals currently being displayed?
    @objc optional var visualSize: iTunesEVSz { get } // the size of the displayed visual
    @objc optional func printPrintDialog(_ printDialog: Bool, withProperties: iTunesPrintSettings!, kind: iTunesEKnd, theme: String!) // Print the specified object(s)
    @objc optional func run() // Run iTunes
    @objc optional func quit() // Quit iTunes
    @objc optional func add(_ x: [URL]!, to: SBObject!) -> iTunesTrack // add one or more files to a playlist
    @objc optional func backTrack() // reposition to beginning of current track or go to previous track if already at start of current track
    @objc optional func convert(_ x: [SBObject]!) -> iTunesTrack // convert one or more files or tracks
    @objc optional func eject() // eject the specified iPod
    @objc optional func fastForward() // skip forward in a playing track
    @objc optional func nextTrack() // advance to the next track in the current playlist
    @objc optional func pause() // pause playback
    @objc optional func playOnce(_ once: Bool) // play the current track or the specified track or file.
    @objc optional func playpause() // toggle the playing/paused state of the current track
    @objc optional func previousTrack() // return to the previous track in the current playlist
    @objc optional func resume() // disable fast forward/rewind and resume playback, if playing.
    @objc optional func rewind() // skip backwards in a playing track
    @objc optional func stop() // stop playback
    @objc optional func subscribe(_ x: String!) // subscribe to a podcast feed
    @objc optional func update() // update the specified iPod
    @objc optional func updateAllPodcasts() // update all subscribed podcast feeds
    @objc optional func updatePodcast() // update podcast feed
    @objc optional func openLocation(_ x: String!) // Opens a Music Store or audio stream URL
    @objc optional func setCurrentAirPlayDevices(_ currentAirPlayDevices: [iTunesAirPlayDevice]!) // the currently selected AirPlay device(s)
    @objc optional func setCurrentEncoder(_ currentEncoder: iTunesEncoder!) // the currently selected encoder (MP3, AIFF, WAV, etc.)
    @objc optional func setCurrentEQPreset(_ currentEQPreset: iTunesEQPreset!) // the currently selected equalizer preset
    @objc optional func setCurrentVisual(_ currentVisual: iTunesVisual!) // the currently selected visual plug-in
    @objc optional func setEQEnabled(_ EQEnabled: Bool) // is the equalizer enabled?
    @objc optional func setFixedIndexing(_ fixedIndexing: Bool) // true if all AppleScript track indices should be independent of the play order of the owning playlist.
    @objc optional func setFrontmost(_ frontmost: Bool) // is iTunes the frontmost application?
    @objc optional func setFullScreen(_ fullScreen: Bool) // are visuals displayed using the entire screen?
    @objc optional func setMute(_ mute: Bool) // has the sound output been muted?
    @objc optional func setPlayerPosition(_ playerPosition: Double) // the player’s position within the currently playing track in seconds.
    @objc optional func setShuffleEnabled(_ shuffleEnabled: Bool) // are songs played in random order?
    @objc optional func setShuffleMode(_ shuffleMode: iTunesEShM) // the playback shuffle mode
    @objc optional func setSongRepeat(_ songRepeat: iTunesERpt) // the playback repeat mode
    @objc optional func setSoundVolume(_ soundVolume: Int) // the sound output volume (0 = minimum, 100 = maximum)
    @objc optional func setVisualsEnabled(_ visualsEnabled: Bool) // are visuals currently being displayed?
    @objc optional func setVisualSize(_ visualSize: iTunesEVSz) // the size of the displayed visual
}
extension SBApplication: iTunesApplication {}

// MARK: iTunesItem
@objc public protocol iTunesItem: SBObjectProtocol, iTunesGenericMethods {
    @objc optional var container: SBObject { get } // the container of the item
    @objc optional func id() -> Int // the id of the item
    @objc optional var index: Int { get } // The index of the item in internal application order.
    @objc optional var name: String { get } // the name of the item
    @objc optional var persistentID: String { get } // the id of the item as a hexadecimal string. This id does not change over time.
    @objc optional var properties: [AnyHashable : Any] { get } // every property of the item
    @objc optional func download() // download a cloud track or playlist, or a podcast episode
    @objc optional func reveal() // reveal and select a track or playlist
    @objc optional func setName(_ name: String!) // the name of the item
    @objc optional func setProperties(_ properties: [AnyHashable : Any]!) // every property of the item
}
extension SBObject: iTunesItem {}

// MARK: iTunesAirPlayDevice
@objc public protocol iTunesAirPlayDevice: iTunesItem {
    @objc optional var active: Bool { get } // is the device currently being played to?
    @objc optional var available: Bool { get } // is the device currently available?
    @objc optional var kind: iTunesEAPD { get } // the kind of the device
    @objc optional var networkAddress: String { get } // the network (MAC) address of the device
    @objc optional func protected() -> Bool // is the device password- or passcode-protected?
    @objc optional var selected: Bool { get } // is the device currently selected?
    @objc optional var supportsAudio: Bool { get } // does the device support audio playback?
    @objc optional var supportsVideo: Bool { get } // does the device support video playback?
    @objc optional var soundVolume: Int { get } // the output volume for the device (0 = minimum, 100 = maximum)
    @objc optional func setSelected(_ selected: Bool) // is the device currently selected?
    @objc optional func setSoundVolume(_ soundVolume: Int) // the output volume for the device (0 = minimum, 100 = maximum)
}
extension SBObject: iTunesAirPlayDevice {}

// MARK: iTunesArtwork
@objc public protocol iTunesArtwork: iTunesItem {
    @objc optional var data: NSImage { get } // data for this artwork, in the form of a picture
    @objc optional var objectDescription: String { get } // description of artwork as a string
    @objc optional var downloaded: Bool { get } // was this artwork downloaded by iTunes?
    @objc optional var format: NSNumber { get } // the data format for this piece of artwork
    @objc optional var kind: Int { get } // kind or purpose of this piece of artwork
    @objc optional var rawData: Data { get } // data for this artwork, in original format
    @objc optional func setData(_ data: NSImage!) // data for this artwork, in the form of a picture
    @objc optional func setObjectDescription(_ objectDescription: String!) // description of artwork as a string
    @objc optional func setKind(_ kind: Int) // kind or purpose of this piece of artwork
    @objc optional func setRawData(_ rawData: Data!) // data for this artwork, in original format
}
extension SBObject: iTunesArtwork {}

// MARK: iTunesEncoder
@objc public protocol iTunesEncoder: iTunesItem {
    @objc optional var format: String { get } // the data format created by the encoder
}
extension SBObject: iTunesEncoder {}

// MARK: iTunesEQPreset
@objc public protocol iTunesEQPreset: iTunesItem {
    @objc optional var band1: Double { get } // the equalizer 32 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional var band2: Double { get } // the equalizer 64 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional var band3: Double { get } // the equalizer 125 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional var band4: Double { get } // the equalizer 250 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional var band5: Double { get } // the equalizer 500 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional var band6: Double { get } // the equalizer 1 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional var band7: Double { get } // the equalizer 2 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional var band8: Double { get } // the equalizer 4 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional var band9: Double { get } // the equalizer 8 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional var band10: Double { get } // the equalizer 16 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional var modifiable: Bool { get } // can this preset be modified?
    @objc optional var preamp: Double { get } // the equalizer preamp level (-12.0 dB to +12.0 dB)
    @objc optional var updateTracks: Bool { get } // should tracks which refer to this preset be updated when the preset is renamed or deleted?
    @objc optional func setBand1(_ band1: Double) // the equalizer 32 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand2(_ band2: Double) // the equalizer 64 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand3(_ band3: Double) // the equalizer 125 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand4(_ band4: Double) // the equalizer 250 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand5(_ band5: Double) // the equalizer 500 Hz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand6(_ band6: Double) // the equalizer 1 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand7(_ band7: Double) // the equalizer 2 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand8(_ band8: Double) // the equalizer 4 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand9(_ band9: Double) // the equalizer 8 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional func setBand10(_ band10: Double) // the equalizer 16 kHz band level (-12.0 dB to +12.0 dB)
    @objc optional func setPreamp(_ preamp: Double) // the equalizer preamp level (-12.0 dB to +12.0 dB)
    @objc optional func setUpdateTracks(_ updateTracks: Bool) // should tracks which refer to this preset be updated when the preset is renamed or deleted?
}
extension SBObject: iTunesEQPreset {}

// MARK: iTunesPlaylist
@objc public protocol iTunesPlaylist: iTunesItem {
    @objc optional func tracks() -> SBElementArray
    @objc optional func artworks() -> SBElementArray
    @objc optional var objectDescription: String { get } // the description of the playlist
    @objc optional var duration: Int { get } // the total length of all songs (in seconds)
    @objc optional var name: String { get } // the name of the playlist
    @objc optional var loved: Bool { get } // is this playlist loved?
    @objc optional var parent: iTunesPlaylist { get } // folder which contains this playlist (if any)
    @objc optional var size: Int { get } // the total size of all songs (in bytes)
    @objc optional var specialKind: iTunesESpK { get } // special playlist kind
    @objc optional var time: String { get } // the length of all songs in MM:SS format
    @objc optional var visible: Bool { get } // is this playlist visible in the Source list?
    @objc optional func moveTo(_ to: SBObject!) // Move playlist(s) to a new location
    @objc optional func searchFor(_ for_: String!, only: iTunesESrA) -> iTunesTrack // search a playlist for tracks matching the search string. Identical to entering search text in the Search field in iTunes.
    @objc optional func setObjectDescription(_ objectDescription: String!) // the description of the playlist
    @objc optional func setName(_ name: String!) // the name of the playlist
    @objc optional func setLoved(_ loved: Bool) // is this playlist loved?
}
extension SBObject: iTunesPlaylist {}

// MARK: iTunesAudioCDPlaylist
@objc public protocol iTunesAudioCDPlaylist: iTunesPlaylist {
    @objc optional func audioCDTracks() -> SBElementArray
    @objc optional var artist: String { get } // the artist of the CD
    @objc optional var compilation: Bool { get } // is this CD a compilation album?
    @objc optional var composer: String { get } // the composer of the CD
    @objc optional var discCount: Int { get } // the total number of discs in this CD’s album
    @objc optional var discNumber: Int { get } // the index of this CD disc in the source album
    @objc optional var genre: String { get } // the genre of the CD
    @objc optional var year: Int { get } // the year the album was recorded/released
    @objc optional func setArtist(_ artist: String!) // the artist of the CD
    @objc optional func setCompilation(_ compilation: Bool) // is this CD a compilation album?
    @objc optional func setComposer(_ composer: String!) // the composer of the CD
    @objc optional func setDiscCount(_ discCount: Int) // the total number of discs in this CD’s album
    @objc optional func setDiscNumber(_ discNumber: Int) // the index of this CD disc in the source album
    @objc optional func setGenre(_ genre: String!) // the genre of the CD
    @objc optional func setYear(_ year: Int) // the year the album was recorded/released
}
extension SBObject: iTunesAudioCDPlaylist {}

// MARK: iTunesLibraryPlaylist
@objc public protocol iTunesLibraryPlaylist: iTunesPlaylist {
    @objc optional func fileTracks() -> SBElementArray
    @objc optional func URLTracks() -> SBElementArray
    @objc optional func sharedTracks() -> SBElementArray
}
extension SBObject: iTunesLibraryPlaylist {}

// MARK: iTunesRadioTunerPlaylist
@objc public protocol iTunesRadioTunerPlaylist: iTunesPlaylist {
    @objc optional func URLTracks() -> SBElementArray
}
extension SBObject: iTunesRadioTunerPlaylist {}

// MARK: iTunesSource
@objc public protocol iTunesSource: iTunesItem {
    @objc optional func audioCDPlaylists() -> SBElementArray
    @objc optional func libraryPlaylists() -> SBElementArray
    @objc optional func playlists() -> SBElementArray
    @objc optional func radioTunerPlaylists() -> SBElementArray
    @objc optional func subscriptionPlaylists() -> SBElementArray
    @objc optional func userPlaylists() -> SBElementArray
    @objc optional var capacity: Int64 { get } // the total size of the source if it has a fixed size
    @objc optional var freeSpace: Int64 { get } // the free space on the source if it has a fixed size
    @objc optional var kind: iTunesESrc { get }
    @objc optional func eject() // eject the specified iPod
    @objc optional func update() // update the specified iPod
}
extension SBObject: iTunesSource {}

// MARK: iTunesSubscriptionPlaylist
@objc public protocol iTunesSubscriptionPlaylist: iTunesPlaylist {
    @objc optional func fileTracks() -> SBElementArray
    @objc optional func URLTracks() -> SBElementArray
}
extension SBObject: iTunesSubscriptionPlaylist {}

// MARK: iTunesUserPlaylist
@objc public protocol iTunesUserPlaylist: iTunesPlaylist {
    @objc optional func fileTracks() -> SBElementArray
    @objc optional func URLTracks() -> SBElementArray
    @objc optional func sharedTracks() -> SBElementArray
    @objc optional var shared: Bool { get } // is this playlist shared?
    @objc optional var smart: Bool { get } // is this a Smart Playlist?
    @objc optional var genius: Bool { get } // is this a Genius Playlist?
    @objc optional func setShared(_ shared: Bool) // is this playlist shared?
}
extension SBObject: iTunesUserPlaylist {}

// MARK: iTunesFolderPlaylist
@objc public protocol iTunesFolderPlaylist: iTunesUserPlaylist {
}
extension SBObject: iTunesFolderPlaylist {}

// MARK: iTunesVisual
@objc public protocol iTunesVisual: iTunesItem {
}
extension SBObject: iTunesVisual {}

// MARK: iTunesWindow
@objc public protocol iTunesWindow: iTunesItem {
    @objc optional var bounds: NSRect { get } // the boundary rectangle for the window
    @objc optional var closeable: Bool { get } // does the window have a close button?
    @objc optional var collapseable: Bool { get } // does the window have a collapse button?
    @objc optional var collapsed: Bool { get } // is the window collapsed?
    @objc optional var fullScreen: Bool { get } // is the window full screen?
    @objc optional var position: NSPoint { get } // the upper left position of the window
    @objc optional var resizable: Bool { get } // is the window resizable?
    @objc optional var visible: Bool { get } // is the window visible?
    @objc optional var zoomable: Bool { get } // is the window zoomable?
    @objc optional var zoomed: Bool { get } // is the window zoomed?
    @objc optional func setBounds(_ bounds: NSRect) // the boundary rectangle for the window
    @objc optional func setCollapsed(_ collapsed: Bool) // is the window collapsed?
    @objc optional func setFullScreen(_ fullScreen: Bool) // is the window full screen?
    @objc optional func setPosition(_ position: NSPoint) // the upper left position of the window
    @objc optional func setVisible(_ visible: Bool) // is the window visible?
    @objc optional func setZoomed(_ zoomed: Bool) // is the window zoomed?
}
extension SBObject: iTunesWindow {}

// MARK: iTunesBrowserWindow
@objc public protocol iTunesBrowserWindow: iTunesWindow {
    @objc optional var selection: SBObject { get } // the selected songs
    @objc optional var view: iTunesPlaylist { get } // the playlist currently displayed in the window
    @objc optional func setView(_ view: iTunesPlaylist!) // the playlist currently displayed in the window
}
extension SBObject: iTunesBrowserWindow {}

// MARK: iTunesEQWindow
@objc public protocol iTunesEQWindow: iTunesWindow {
}
extension SBObject: iTunesEQWindow {}

// MARK: iTunesMiniplayerWindow
@objc public protocol iTunesMiniplayerWindow: iTunesWindow {
}
extension SBObject: iTunesMiniplayerWindow {}

// MARK: iTunesPlaylistWindow
@objc public protocol iTunesPlaylistWindow: iTunesWindow {
    @objc optional var selection: SBObject { get } // the selected songs
    @objc optional var view: iTunesPlaylist { get } // the playlist displayed in the window
}
extension SBObject: iTunesPlaylistWindow {}

// MARK: iTunesVideoWindow
@objc public protocol iTunesVideoWindow: iTunesWindow {
}
extension SBObject: iTunesVideoWindow {}
