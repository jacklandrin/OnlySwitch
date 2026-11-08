import AppKit
import ScriptingBridge

// MARK: iTunesTrack
@objc public protocol iTunesTrack: iTunesItem {
    @objc optional func artworks() -> SBElementArray
    @objc optional var album: String { get } // the album name of the track
    @objc optional var albumArtist: String { get } // the album artist of the track
    @objc optional var albumLoved: Bool { get } // is the album for this track loved?
    @objc optional var albumRating: Int { get } // the rating of the album for this track (0 to 100)
    @objc optional var albumRatingKind: iTunesERtK { get } // the rating kind of the album rating for this track
    @objc optional var artist: String { get } // the artist/source of the track
    @objc optional var bitRate: Int { get } // the bit rate of the track (in kbps)
    @objc optional var bookmark: Double { get } // the bookmark time of the track in seconds
    @objc optional var bookmarkable: Bool { get } // is the playback position for this track remembered?
    @objc optional var bpm: Int { get } // the tempo of this track in beats per minute
    @objc optional var category: String { get } // the category of the track
    @objc optional var cloudStatus: iTunesEClS { get } // the iCloud status of the track
    @objc optional var comment: String { get } // freeform notes about the track
    @objc optional var compilation: Bool { get } // is this track from a compilation album?
    @objc optional var composer: String { get } // the composer of the track
    @objc optional var databaseID: Int { get } // the common, unique ID for this track. If two tracks in different playlists have the same database ID, they are sharing the same data.
    @objc optional var dateAdded: Date { get } // the date the track was added to the playlist
    @objc optional var objectDescription: String { get } // the description of the track
    @objc optional var discCount: Int { get } // the total number of discs in the source album
    @objc optional var discNumber: Int { get } // the index of the disc containing this track on the source album
    @objc optional var downloaderAppleID: String { get } // the Apple ID of the person who downloaded this track
    @objc optional var downloaderName: String { get } // the name of the person who downloaded this track
    @objc optional var duration: Double { get } // the length of the track in seconds
    @objc optional var enabled: Bool { get } // is this track checked for playback?
    @objc optional var episodeID: String { get } // the episode ID of the track
    @objc optional var episodeNumber: Int { get } // the episode number of the track
    @objc optional var EQ: String { get } // the name of the EQ preset of the track
    @objc optional var finish: Double { get } // the stop time of the track in seconds
    @objc optional var gapless: Bool { get } // is this track from a gapless album?
    @objc optional var genre: String { get } // the music/audio genre (category) of the track
    @objc optional var grouping: String { get } // the grouping (piece) of the track. Generally used to denote movements within a classical work.
    @objc optional var kind: String { get } // a text description of the track
    @objc optional var longDescription: String { get }
    @objc optional var loved: Bool { get } // is this track loved?
    @objc optional var lyrics: String { get } // the lyrics of the track
    @objc optional var mediaKind: iTunesEMdK { get } // the media kind of the track
    @objc optional var modificationDate: Date { get } // the modification date of the content of this track
    @objc optional var playedCount: Int { get } // number of times this track has been played
    @objc optional var playedDate: Date { get } // the date and time this track was last played
    @objc optional var purchaserAppleID: String { get } // the Apple ID of the person who purchased this track
    @objc optional var purchaserName: String { get } // the name of the person who purchased this track
    @objc optional var rating: Int { get } // the rating of this track (0 to 100)
    @objc optional var ratingKind: iTunesERtK { get } // the rating kind of this track
    @objc optional var releaseDate: Date { get } // the release date of this track
    @objc optional var sampleRate: Int { get } // the sample rate of the track (in Hz)
    @objc optional var seasonNumber: Int { get } // the season number of the track
    @objc optional var shufflable: Bool { get } // is this track included when shuffling?
    @objc optional var skippedCount: Int { get } // number of times this track has been skipped
    @objc optional var skippedDate: Date { get } // the date and time this track was last skipped
    @objc optional var show: String { get } // the show name of the track
    @objc optional var sortAlbum: String { get } // override string to use for the track when sorting by album
    @objc optional var sortArtist: String { get } // override string to use for the track when sorting by artist
    @objc optional var sortAlbumArtist: String { get } // override string to use for the track when sorting by album artist
    @objc optional var sortName: String { get } // override string to use for the track when sorting by name
    @objc optional var sortComposer: String { get } // override string to use for the track when sorting by composer
    @objc optional var sortShow: String { get } // override string to use for the track when sorting by show name
    @objc optional var size: Int64 { get } // the size of the track (in bytes)
    @objc optional var start: Double { get } // the start time of the track in seconds
    @objc optional var time: String { get } // the length of the track in MM:SS format
    @objc optional var trackCount: Int { get } // the total number of tracks on the source album
    @objc optional var trackNumber: Int { get } // the index of the track on the source album
    @objc optional var unplayed: Bool { get } // is this track unplayed?
    @objc optional var videoKind: iTunesEVdK { get } // kind of video track
    @objc optional var volumeAdjustment: Int { get } // relative volume adjustment of the track (-100% to 100%)
    @objc optional var year: Int { get } // the year the track was recorded/released
    @objc optional func setAlbum(_ album: String!) // the album name of the track
    @objc optional func setAlbumArtist(_ albumArtist: String!) // the album artist of the track
    @objc optional func setAlbumLoved(_ albumLoved: Bool) // is the album for this track loved?
    @objc optional func setAlbumRating(_ albumRating: Int) // the rating of the album for this track (0 to 100)
    @objc optional func setArtist(_ artist: String!) // the artist/source of the track
    @objc optional func setBookmark(_ bookmark: Double) // the bookmark time of the track in seconds
    @objc optional func setBookmarkable(_ bookmarkable: Bool) // is the playback position for this track remembered?
    @objc optional func setBpm(_ bpm: Int) // the tempo of this track in beats per minute
    @objc optional func setCategory(_ category: String!) // the category of the track
    @objc optional func setComment(_ comment: String!) // freeform notes about the track
    @objc optional func setCompilation(_ compilation: Bool) // is this track from a compilation album?
    @objc optional func setComposer(_ composer: String!) // the composer of the track
    @objc optional func setObjectDescription(_ objectDescription: String!) // the description of the track
    @objc optional func setDiscCount(_ discCount: Int) // the total number of discs in the source album
    @objc optional func setDiscNumber(_ discNumber: Int) // the index of the disc containing this track on the source album
    @objc optional func setEnabled(_ enabled: Bool) // is this track checked for playback?
    @objc optional func setEpisodeID(_ episodeID: String!) // the episode ID of the track
    @objc optional func setEpisodeNumber(_ episodeNumber: Int) // the episode number of the track
    @objc optional func setEQ(_ EQ: String!) // the name of the EQ preset of the track
    @objc optional func setFinish(_ finish: Double) // the stop time of the track in seconds
    @objc optional func setGapless(_ gapless: Bool) // is this track from a gapless album?
    @objc optional func setGenre(_ genre: String!) // the music/audio genre (category) of the track
    @objc optional func setGrouping(_ grouping: String!) // the grouping (piece) of the track. Generally used to denote movements within a classical work.
    @objc optional func setLongDescription(_ longDescription: String!)
    @objc optional func setLoved(_ loved: Bool) // is this track loved?
    @objc optional func setLyrics(_ lyrics: String!) // the lyrics of the track
    @objc optional func setMediaKind(_ mediaKind: iTunesEMdK) // the media kind of the track
    @objc optional func setPlayedCount(_ playedCount: Int) // number of times this track has been played
    @objc optional func setPlayedDate(_ playedDate: Date!) // the date and time this track was last played
    @objc optional func setRating(_ rating: Int) // the rating of this track (0 to 100)
    @objc optional func setSeasonNumber(_ seasonNumber: Int) // the season number of the track
    @objc optional func setShufflable(_ shufflable: Bool) // is this track included when shuffling?
    @objc optional func setSkippedCount(_ skippedCount: Int) // number of times this track has been skipped
    @objc optional func setSkippedDate(_ skippedDate: Date!) // the date and time this track was last skipped
    @objc optional func setShow(_ show: String!) // the show name of the track
    @objc optional func setSortAlbum(_ sortAlbum: String!) // override string to use for the track when sorting by album
    @objc optional func setSortArtist(_ sortArtist: String!) // override string to use for the track when sorting by artist
    @objc optional func setSortAlbumArtist(_ sortAlbumArtist: String!) // override string to use for the track when sorting by album artist
    @objc optional func setSortName(_ sortName: String!) // override string to use for the track when sorting by name
    @objc optional func setSortComposer(_ sortComposer: String!) // override string to use for the track when sorting by composer
    @objc optional func setSortShow(_ sortShow: String!) // override string to use for the track when sorting by show name
    @objc optional func setStart(_ start: Double) // the start time of the track in seconds
    @objc optional func setTrackCount(_ trackCount: Int) // the total number of tracks on the source album
    @objc optional func setTrackNumber(_ trackNumber: Int) // the index of the track on the source album
    @objc optional func setUnplayed(_ unplayed: Bool) // is this track unplayed?
    @objc optional func setVideoKind(_ videoKind: iTunesEVdK) // kind of video track
    @objc optional func setVolumeAdjustment(_ volumeAdjustment: Int) // relative volume adjustment of the track (-100% to 100%)
    @objc optional func setYear(_ year: Int) // the year the track was recorded/released
}
extension SBObject: iTunesTrack {}

// MARK: iTunesAudioCDTrack
@objc public protocol iTunesAudioCDTrack: iTunesTrack {
    @objc optional var location: URL { get } // the location of the file represented by this track
}
extension SBObject: iTunesAudioCDTrack {}

// MARK: iTunesFileTrack
@objc public protocol iTunesFileTrack: iTunesTrack {
    @objc optional var location: URL { get } // the location of the file represented by this track
    @objc optional func refresh() // update file track information from the current information in the track’s file
    @objc optional func setLocation(_ location: URL!) // the location of the file represented by this track
}
extension SBObject: iTunesFileTrack {}

// MARK: iTunesSharedTrack
@objc public protocol iTunesSharedTrack: iTunesTrack {
}
extension SBObject: iTunesSharedTrack {}

// MARK: iTunesURLTrack
@objc public protocol iTunesURLTrack: iTunesTrack {
    @objc optional var address: String { get } // the URL for this track
    @objc optional func setAddress(_ address: String!) // the URL for this track
}
extension SBObject: iTunesURLTrack {}
