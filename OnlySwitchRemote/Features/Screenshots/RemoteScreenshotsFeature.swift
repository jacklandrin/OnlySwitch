import ComposableArchitecture
import Foundation
import RemoteCore

/// Mirrors the selected Mac's screenshots and screen recordings (view, play, copy images, delete; never edit).
///
/// Streams only while visible, entitled and authenticated, like Brightness. Every request is sent
/// after the subscription; stopping the stream cancels streaming, thumbnail, image and delete work.
/// Hidden (for example backgrounded) with an original still downloading, the stream is held for
/// that download only, bounded by `backgroundTransferGracePeriod`, so a drag that left the app can
/// still be served. `CancellationError` (caller cancelled, superseded transfer, unsubscribe,
/// disconnect) is silent.
@Reducer
struct RemoteScreenshotsFeature {
    @ObservableState
    struct State: Equatable {
        var selectedMacID: UUID?
        var connectionState: DashboardFeature.ConnectionState = .idle
        var isVisible = false
        var isEntitled = false
        /// A subscription request was sent and not yet withdrawn; libraries are accepted from this point.
        var isStreamRequested = false
        var isStreaming = false
        /// Live library, or the cached one while offline. Only ever a library received from the Mac.
        var library: RemoteScreenshotLibrary?
        /// True once the current subscription delivered a library; false while showing the cache.
        var hasLiveLibrary = false
        /// A `replaceLibrary` call is running; saves are serialized so an older one never lands last.
        var isSavingLibrary = false
        /// `library` has been written to the cache, so thumbnails can be requested and stored for it.
        var isLibrarySaved = false
        var thumbnailURLs: [UUID: URL] = [:]
        var imageURLs: [UUID: URL] = [:]
        var loadingThumbnailIDs: Set<UUID> = []
        var downloadingItemIDs: Set<UUID> = []
        /// Downloads started by Copy; a view-only download never copies.
        var pendingCopyIDs: Set<UUID> = []
        /// Hidden while originals were downloading: the subscription is kept only until they end.
        var isHoldingTransfers = false
        var deletingItemIDs: Set<UUID> = []
        /// Display-only: deleted on the Mac and hidden until the next received library reconciles.
        var removedItemIDs: Set<UUID> = []
        var selectedItemID: UUID?
        var pendingDeleteItemID: UUID?
        var copiedItemID: UUID?
        var availabilityMessage: String?
        var operationError: String?
        /// Bumped on Mac change and transient resets; async results carrying an older value are dropped.
        var cacheGeneration: UInt64 = 0
        /// The reducer's image client, handed to drag providers built in views. Not part of equality.
        var dragImages = RemoteScreenshotDragImages()

        var items: [RemoteScreenshotItem] {
            guard let library else { return [] }
            guard removedItemIDs.isEmpty == false else { return library.items }
            return library.items.filter { removedItemIDs.contains($0.id) == false }
        }

        var shouldStream: Bool {
            isVisible && isEntitled && selectedMacID != nil && connectionState == .authenticated
        }

        /// Showing cached data without a live connection.
        var isOffline: Bool { connectionState != .authenticated }

        var canDelete: Bool { isStreaming && hasLiveLibrary && connectionState == .authenticated }

        func item(_ id: UUID) -> RemoteScreenshotItem? { items.first { $0.id == id } }

        func isDownloading(_ id: UUID) -> Bool { downloadingItemIDs.contains(id) }

        func isDeleting(_ id: UUID) -> Bool { deletingItemIDs.contains(id) }
    }

    enum Action: Equatable {
        case visibilityChanged(Bool)
        case entitlementChanged(Bool)
        /// The root's selected Mac or its connection state changed outside a connection event.
        case contextChanged(macID: UUID?, connectionState: DashboardFeature.ConnectionState)
        case connectionEvent(RemoteConnectionEvent)
        case streamingResponse(Result<Bool, RemoteProtocolError>)
        case cacheLoaded(generation: UInt64, RemoteScreenshotCacheSnapshot?)
        case libraryCached(generation: UInt64, RemoteScreenshotCacheSnapshot)
        case thumbnailsLoaded(generation: UInt64, libraryRevision: UInt64, [UUID: URL], failedIDs: [UUID])
        case itemTapped(UUID)
        case detailDismissed
        case copyTapped(UUID)
        /// A drag began; an uncached original starts downloading now, before the app may leave the foreground.
        case dragStarted(UUID)
        case imageLoaded(generation: UInt64, itemID: UUID, URL)
        case imageFailed(generation: UInt64, itemID: UUID, RemoteProtocolError)
        case imageCancelled(generation: UInt64, itemID: UUID)
        case transferHoldExpired
        case copyFinished(UUID, Bool)
        case copyFeedbackExpired(UUID)
        case deleteTapped(UUID)
        case deleteConfirmed
        case deleteCancelled
        case deleteResponse(generation: UInt64, UUID, Result<RemoteScreenshotDeleteResult, RemoteProtocolError>)
        case deleteInterrupted(generation: UInt64, UUID)
        case errorDismissed
    }

    static let copyFeedbackDuration: Duration = .seconds(1.2)
    /// How long a hidden tab keeps its subscription for in-flight originals.
    static let backgroundTransferGracePeriod: Duration = .seconds(30)

    @Dependency(\.remoteConnection) var connection
    @Dependency(\.remoteScreenshotCache) var cache
    @Dependency(\.remoteScreenshotImages) var images
    @Dependency(\.remoteScreenshotPasteboard) var pasteboard
    @Dependency(\.continuousClock) var clock
    @Dependency(\.uuid) var uuid

    enum CancelID: Hashable {
        case streaming, cacheLoad, thumbnails, image(UUID), delete(UUID), copyFeedback, transferHold
    }

    /// Why an original is being downloaded. A drag only prefetches: the drag provider joins the
    /// same single-flight load when the drop target asks for the file.
    enum Intent: Equatable { case copy, view, drag }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .visibilityChanged(isVisible):
                state.isVisible = isVisible
                // The tab must be visible before any cell can be dragged, so this is always set in time.
                state.dragImages = .init(client: images)
                return .concatenate(loadCacheIfNeeded(state), reconcile(&state))

            case let .entitlementChanged(isEntitled):
                state.isEntitled = isEntitled
                return .concatenate(loadCacheIfNeeded(state), reconcile(&state))

            case let .contextChanged(macID, connectionState):
                var effects: [Effect<Action>] = []
                if macID != state.selectedMacID {
                    effects.append(cancelWork(state))
                    resetForMac(macID, state: &state)
                    state.connectionState = connectionState
                } else if connectionState != state.connectionState {
                    if connectionState == .authenticated {
                        state.connectionState = .authenticated
                    } else {
                        effects.append(resetTransientState(&state, connectionState: connectionState))
                    }
                }
                return .merge(effects + [.concatenate(loadCacheIfNeeded(state), reconcile(&state))])

            case .streamingResponse(.success):
                guard state.isStreamRequested, state.shouldStream else { return .none }
                state.isStreaming = true
                return fetchMissingThumbnails(&state)

            case let .streamingResponse(.failure(error)):
                state.isStreaming = false
                state.availabilityMessage = Self.availabilityMessage(for: error)
                return .none

            case let .connectionEvent(event):
                return handle(event, state: &state)

            case let .cacheLoaded(generation, snapshot):
                guard generation == state.cacheGeneration, state.hasLiveLibrary == false, let snapshot else { return .none }
                state.library = snapshot.library
                state.thumbnailURLs = snapshot.thumbnailURLs
                state.imageURLs = snapshot.imageURLs
                return .none

            case let .libraryCached(generation, snapshot):
                state.isSavingLibrary = false
                if generation == state.cacheGeneration, state.hasLiveLibrary, snapshot.library == state.library {
                    state.isLibrarySaved = true
                    state.thumbnailURLs = snapshot.thumbnailURLs
                    state.imageURLs = snapshot.imageURLs
                    return fetchMissingThumbnails(&state)
                }
                // A newer library arrived while saving: save it now, after the older save finished.
                return saveLibraryIfNeeded(&state)

            case let .thumbnailsLoaded(generation, libraryRevision, urls, failedIDs):
                guard generation == state.cacheGeneration, libraryRevision == state.library?.revision else { return .none }
                let ids = Set(state.items.map(\.id))
                for (id, url) in urls where ids.contains(id) { state.thumbnailURLs[id] = url }
                state.loadingThumbnailIDs.subtract(urls.keys)
                state.loadingThumbnailIDs.subtract(failedIDs)
                return .none

            case let .itemTapped(id):
                guard let item = state.item(id) else { return .none }
                state.selectedItemID = id
                return state.imageURLs[id] == nil ? download(item, intent: .view, state: &state) : .none

            case .detailDismissed:
                state.selectedItemID = nil
                return .none

            case let .copyTapped(id):
                // Recordings are never put on the pasteboard.
                guard let item = state.item(id), item.isRecording == false else { return .none }
                if let url = state.imageURLs[id] { return copy(url, item: item) }
                return download(item, intent: .copy, state: &state)

            case let .dragStarted(id):
                guard let item = state.item(id), state.imageURLs[id] == nil else { return .none }
                return download(item, intent: .drag, state: &state)

            case let .imageLoaded(generation, itemID, url):
                guard generation == state.cacheGeneration else { return .none }
                let wasCopy = state.pendingCopyIDs.remove(itemID) != nil
                state.downloadingItemIDs.remove(itemID)
                state.imageURLs[itemID] = url
                let hold = reconcileTransferHold(&state)
                guard wasCopy, let item = state.item(itemID) else { return hold }
                return .merge(copy(url, item: item), hold)

            case let .imageFailed(generation, itemID, error):
                guard generation == state.cacheGeneration else { return .none }
                state.downloadingItemIDs.remove(itemID)
                state.pendingCopyIDs.remove(itemID)
                state.operationError = Self.downloadErrorMessage(for: error, isRecording: state.item(itemID)?.isRecording == true)
                return reconcileTransferHold(&state)

            case let .imageCancelled(generation, itemID):
                guard generation == state.cacheGeneration else { return .none }
                state.downloadingItemIDs.remove(itemID)
                state.pendingCopyIDs.remove(itemID)
                return reconcileTransferHold(&state)

            case .transferHoldExpired:
                guard state.isHoldingTransfers else { return .none }
                return stopStream(&state)

            case let .copyFinished(id, succeeded):
                guard succeeded else {
                    state.operationError = String(localized: "The screenshot could not be copied.")
                    return .none
                }
                state.copiedItemID = id
                return .run { [clock] send in
                    try await clock.sleep(for: Self.copyFeedbackDuration)
                    await send(.copyFeedbackExpired(id))
                } catch: { _, _ in }
                .cancellable(id: CancelID.copyFeedback, cancelInFlight: true)

            case let .copyFeedbackExpired(id):
                if state.copiedItemID == id { state.copiedItemID = nil }
                return .none

            case let .deleteTapped(id):
                guard state.canDelete, state.item(id) != nil, state.deletingItemIDs.contains(id) == false else { return .none }
                state.pendingDeleteItemID = id
                return .none

            case .deleteCancelled:
                state.pendingDeleteItemID = nil
                return .none

            case .deleteConfirmed:
                guard let id = state.pendingDeleteItemID else { return .none }
                state.pendingDeleteItemID = nil
                guard state.canDelete, let macID = state.selectedMacID, state.item(id) != nil,
                      state.deletingItemIDs.contains(id) == false else { return .none }
                state.deletingItemIDs.insert(id)
                if state.selectedItemID == id { state.selectedItemID = nil }
                let generation = state.cacheGeneration
                let request = RemoteScreenshotDeleteRequest(requestID: uuid(), ids: [id])
                return .run { [connection] send in
                    do {
                        let result = try await connection.deleteScreenshots(.init(macID: macID, request: request))
                        await send(.deleteResponse(generation: generation, id, .success(result)))
                    } catch is CancellationError {
                        await send(.deleteInterrupted(generation: generation, id))
                    } catch let error as RemoteProtocolError {
                        await send(.deleteResponse(generation: generation, id, .failure(error)))
                    } catch {
                        await send(.deleteResponse(generation: generation, id, .failure(Self.unexpected(error))))
                    }
                }
                .cancellable(id: CancelID.delete(id), cancelInFlight: true)

            case let .deleteResponse(generation, id, result):
                guard generation == state.cacheGeneration else { return .none }
                state.deletingItemIDs.remove(id)
                switch result {
                case let .success(value) where value.failedIDs.contains(id) == false:
                    // Hidden until the next library (about 1 s later); the cache keeps the received library.
                    state.removedItemIDs.insert(id)
                    if state.selectedItemID == id { state.selectedItemID = nil }
                    if state.copiedItemID == id { state.copiedItemID = nil }
                case .success:
                    state.operationError = String(localized: "The Mac could not move the screenshot to the Trash.")
                case let .failure(error):
                    state.operationError = Self.deleteErrorMessage(for: error)
                }
                return .none

            case let .deleteInterrupted(generation, id):
                guard generation == state.cacheGeneration else { return .none }
                state.deletingItemIDs.remove(id)
                return .none

            case .errorDismissed:
                state.operationError = nil
                return .none
            }
        }
    }
}
