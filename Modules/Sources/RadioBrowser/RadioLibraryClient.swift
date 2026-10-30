import Dependencies
import Foundation

/// The user's station list and the shared radio player. The app supplies the live value
/// (Core Data, `RadioStationSwitch`, file panels); this module only sees this interface.
public struct RadioLibraryClient: Sendable {
    public var favorites: @MainActor @Sendable () throws -> [RadioFavorite]
    public var add: @MainActor @Sendable (_ station: RadioFavoriteDraft.Valid, _ favicon: URL?, _ browserStationID: String?) throws -> RadioFavorite
    public var update: @MainActor @Sendable (_ id: UUID, _ station: RadioFavoriteDraft.Valid) throws -> Void
    public var delete: @MainActor @Sendable (UUID) throws -> Void
    /// Selects a favorite as the current station and starts playing it.
    public var play: @MainActor @Sendable (UUID) -> Void
    /// Plays or stops the current station.
    public var togglePlayback: @MainActor @Sendable () -> Void
    /// Auditions a browser station without changing the selected favorite.
    public var preview: @MainActor @Sendable (RadioBrowserStation) -> Void
    /// Ends an audition and restores the selected favorite.
    public var stopPreview: @MainActor @Sendable () -> Void
    public var playbackStatus: @MainActor @Sendable () -> RadioPlaybackStatus
    public var playbackUpdates: @Sendable () -> AsyncStream<RadioPlaybackStatus>
    /// Returns the number of imported stations, or `nil` if the user cancelled.
    public var importStations: @MainActor @Sendable () async throws -> Int?
    /// Returns `false` if the user cancelled.
    public var exportStations: @MainActor @Sendable () async throws -> Bool
    public var copyToPasteboard: @MainActor @Sendable (String) -> Void

    public init(
        favorites: @escaping @MainActor @Sendable () throws -> [RadioFavorite],
        add: @escaping @MainActor @Sendable (RadioFavoriteDraft.Valid, URL?, String?) throws -> RadioFavorite,
        update: @escaping @MainActor @Sendable (UUID, RadioFavoriteDraft.Valid) throws -> Void,
        delete: @escaping @MainActor @Sendable (UUID) throws -> Void,
        play: @escaping @MainActor @Sendable (UUID) -> Void,
        togglePlayback: @escaping @MainActor @Sendable () -> Void,
        preview: @escaping @MainActor @Sendable (RadioBrowserStation) -> Void,
        stopPreview: @escaping @MainActor @Sendable () -> Void,
        playbackStatus: @escaping @MainActor @Sendable () -> RadioPlaybackStatus,
        playbackUpdates: @escaping @Sendable () -> AsyncStream<RadioPlaybackStatus>,
        importStations: @escaping @MainActor @Sendable () async throws -> Int?,
        exportStations: @escaping @MainActor @Sendable () async throws -> Bool,
        copyToPasteboard: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.favorites = favorites; self.add = add; self.update = update; self.delete = delete
        self.play = play; self.togglePlayback = togglePlayback; self.preview = preview; self.stopPreview = stopPreview
        self.playbackStatus = playbackStatus; self.playbackUpdates = playbackUpdates
        self.importStations = importStations; self.exportStations = exportStations; self.copyToPasteboard = copyToPasteboard
    }
}

extension RadioLibraryClient: TestDependencyKey {
    public static let testValue = Self(
        favorites: unimplemented("RadioLibraryClient.favorites", placeholder: []),
        add: { _, _, _ in
            reportIssue("Unimplemented: RadioLibraryClient.add")
            throw RadioLibraryError.storeUnavailable("unimplemented")
        },
        update: unimplemented("RadioLibraryClient.update"),
        delete: unimplemented("RadioLibraryClient.delete"),
        play: unimplemented("RadioLibraryClient.play"),
        togglePlayback: unimplemented("RadioLibraryClient.togglePlayback"),
        preview: unimplemented("RadioLibraryClient.preview"),
        stopPreview: unimplemented("RadioLibraryClient.stopPreview"),
        playbackStatus: unimplemented("RadioLibraryClient.playbackStatus", placeholder: RadioPlaybackStatus()),
        playbackUpdates: unimplemented("RadioLibraryClient.playbackUpdates", placeholder: .finished),
        importStations: unimplemented("RadioLibraryClient.importStations", placeholder: nil),
        exportStations: unimplemented("RadioLibraryClient.exportStations", placeholder: false),
        copyToPasteboard: unimplemented("RadioLibraryClient.copyToPasteboard")
    )

    /// An in-memory library for previews.
    public static let previewValue: Self = {
        let stations = [
            RadioFavorite(id: UUID(), name: "Country Radio", streamURL: "https://live.leanstream.co/CKRYFM", favicon: nil, browserStationID: nil),
            RadioFavorite(id: UUID(), name: "Dance UK", streamURL: "http://uk2.internet-radio.com:8024/stream", favicon: nil, browserStationID: nil)
        ]
        return Self(
            favorites: { stations },
            add: { station, favicon, id in RadioFavorite(id: UUID(), name: station.name, streamURL: station.streamURL, favicon: favicon, browserStationID: id) },
            update: { _, _ in },
            delete: { _ in },
            play: { _ in },
            togglePlayback: {},
            preview: { _ in },
            stopPreview: {},
            playbackStatus: { RadioPlaybackStatus(currentID: stations.first?.id, isPlaying: true) },
            playbackUpdates: { .finished },
            importStations: { 0 },
            exportStations: { true },
            copyToPasteboard: { _ in }
        )
    }()
}

public extension DependencyValues {
    var radioLibraryClient: RadioLibraryClient {
        get { self[RadioLibraryClient.self] }
        set { self[RadioLibraryClient.self] = newValue }
    }
}

/// A transient confirmation or failure shown above the station lists.
public enum RadioMessage: Equatable, Sendable {
    case added(String)
    case alreadyInFavorites(String)
    case saved(String)
    case deleted(String)
    case imported(Int)
    case exported
    case atLeastOneStation
    case failure(String)

    public var isError: Bool {
        switch self {
        case .alreadyInFavorites, .atLeastOneStation, .failure: true
        case .added, .saved, .deleted, .imported, .exported: false
        }
    }
}

extension RadioLibraryError {
    init(_ error: any Error) {
        self = error as? RadioLibraryError ?? .storeUnavailable(error.localizedDescription)
    }

    var message: RadioMessage {
        switch self {
        case .atLeastOneStation: .atLeastOneStation
        case let .storeUnavailable(detail), let .importFailed(detail), let .exportFailed(detail): .failure(detail)
        }
    }
}
