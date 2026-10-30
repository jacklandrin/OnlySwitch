#if os(macOS)
import Foundation
@testable import RadioBrowser

/// An in-memory `RadioLibraryClient` that records what reducers asked it to do.
@MainActor
final class FakeRadioLibrary {
    var favorites: [RadioFavorite]
    var status = RadioPlaybackStatus()
    var failure: RadioLibraryError?
    var importResult: Int? = 0
    private(set) var added: [(RadioFavoriteDraft.Valid, URL?, String?)] = []
    private(set) var updated: [(UUID, RadioFavoriteDraft.Valid)] = []
    private(set) var deleted: [UUID] = []
    private(set) var played: [UUID] = []
    private(set) var toggles = 0
    private(set) var previewed: [String] = []
    private(set) var stopPreviews = 0
    private(set) var copied: [String] = []
    private var nextID = 100
    let updates = AsyncStream<RadioPlaybackStatus>.makeStream()

    init(favorites: [RadioFavorite] = []) {
        self.favorites = favorites
    }

    var client: RadioLibraryClient {
        RadioLibraryClient(
            favorites: { [self] in
                if let failure { throw failure }
                return favorites
            },
            add: { [self] station, favicon, browserID in
                if let failure { throw failure }
                added.append((station, favicon, browserID))
                nextID += 1
                let favorite = RadioFavorite(id: RadioBrowserFixtures.favorite(nextID).id, name: station.name, streamURL: station.streamURL, favicon: favicon, browserStationID: browserID)
                favorites.append(favorite)
                return favorite
            },
            update: { [self] id, station in
                if let failure { throw failure }
                updated.append((id, station))
                if let index = favorites.firstIndex(where: { $0.id == id }) {
                    favorites[index].name = station.name
                    favorites[index].streamURL = station.streamURL
                }
            },
            delete: { [self] id in
                if let failure { throw failure }
                deleted.append(id)
                favorites.removeAll { $0.id == id }
            },
            play: { [self] in played.append($0) },
            togglePlayback: { [self] in toggles += 1 },
            preview: { [self] in previewed.append($0.id) },
            stopPreview: { [self] in stopPreviews += 1 },
            playbackStatus: { [self] in status },
            playbackUpdates: { [stream = updates.stream] in stream },
            importStations: { [self] in
                if let failure { throw failure }
                return importResult
            },
            exportStations: { [self] in
                if let failure { throw failure }
                return true
            },
            copyToPasteboard: { [self] in copied.append($0) }
        )
    }
}
#endif
