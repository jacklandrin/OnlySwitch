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

    @Dependency(\.remoteConnection) private var connection
    @Dependency(\.remoteScreenshotCache) private var cache
    @Dependency(\.remoteScreenshotImages) private var images
    @Dependency(\.remoteScreenshotPasteboard) private var pasteboard
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.uuid) private var uuid

    fileprivate enum CancelID: Hashable {
        case streaming, cacheLoad, thumbnails, image(UUID), delete(UUID), copyFeedback, transferHold
    }

    /// Why an original is being downloaded. A drag only prefetches: the drag provider joins the
    /// same single-flight load when the drop target asks for the file.
    fileprivate enum Intent: Equatable { case copy, view, drag }

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

// MARK: - Effects

private extension RemoteScreenshotsFeature {
    func handle(_ event: RemoteConnectionEvent, state: inout State) -> Effect<Action> {
        switch event {
        case let .authenticated(id):
            guard id == state.selectedMacID else { return .none }
            state.connectionState = .authenticated
            return reconcile(&state)
        case let .screenshots(id, library):
            guard id == state.selectedMacID,
                  state.isStreamRequested,
                  state.hasLiveLibrary == false || library.revision > state.library?.revision ?? 0 else { return .none }
            state.library = library
            state.hasLiveLibrary = true
            state.isLibrarySaved = false
            state.removedItemIDs = []
            let ids = Set(library.items.map(\.id))
            if let selected = state.selectedItemID, ids.contains(selected) == false { state.selectedItemID = nil }
            if let pending = state.pendingDeleteItemID, ids.contains(pending) == false { state.pendingDeleteItemID = nil }
            if let copied = state.copiedItemID, ids.contains(copied) == false { state.copiedItemID = nil }
            return saveLibraryIfNeeded(&state)
        case let .connecting(id), let .sessionStarted(id, _):
            guard id == state.selectedMacID else { return .none }
            return resetTransientState(&state, connectionState: .connecting)
        case let .offline(id, reason):
            guard id == state.selectedMacID else { return .none }
            return resetTransientState(&state, connectionState: .offline(reason))
        case let .revoked(id):
            guard id == state.selectedMacID else { return .none }
            return resetTransientState(&state, connectionState: .revoked)
        case .persistenceRestored, .catalog, .catalogInvalidated, .statusSnapshot, .status, .action,
             .soundMixer, .systemMonitor, .brightness, .aphroditeLibraryChanged:
            return .none
        }
    }

    func loadCacheIfNeeded(_ state: State) -> Effect<Action> {
        guard state.isVisible, state.isEntitled, state.library == nil, let macID = state.selectedMacID else { return .none }
        let generation = state.cacheGeneration
        return .run { [cache] send in
            await send(.cacheLoaded(generation: generation, await cache.load(macID)))
        }
        .cancellable(id: CancelID.cacheLoad, cancelInFlight: true)
    }

    /// Persists the current live library, one save at a time. Never cancelled: each save must report
    /// back so the next one can start, and only received libraries are ever written.
    func saveLibraryIfNeeded(_ state: inout State) -> Effect<Action> {
        guard state.isSavingLibrary == false, state.hasLiveLibrary, state.isLibrarySaved == false,
              let macID = state.selectedMacID, let library = state.library else { return .none }
        state.isSavingLibrary = true
        let generation = state.cacheGeneration
        return .run { [cache] send in
            await send(.libraryCached(generation: generation, await cache.replaceLibrary(macID, library)))
        }
    }

    func reconcile(_ state: inout State) -> Effect<Action> {
        if state.shouldStream {
            if state.isHoldingTransfers {
                // Back before the held downloads ended: the subscription is still live.
                state.isHoldingTransfers = false
                return .merge(.cancel(id: CancelID.transferHold), fetchMissingThumbnails(&state))
            }
            guard state.isStreamRequested == false else { return .none }
            state.isStreamRequested = true
            state.availabilityMessage = nil
            return setStreaming(true)
        }
        guard state.isStreamRequested else { return .cancel(id: CancelID.streaming) }
        if canHoldTransfers(state) {
            return state.isHoldingTransfers ? .none : beginTransferHold(&state)
        }
        return stopStream(&state)
    }

    /// Only hiding holds the stream: losing the entitlement, connection or Mac stops it at once.
    func canHoldTransfers(_ state: State) -> Bool {
        state.isVisible == false && state.isEntitled && state.selectedMacID != nil
            && state.connectionState == .authenticated && state.downloadingItemIDs.isEmpty == false
    }

    /// Keeps the subscription and the original downloads; thumbnails and deletes stop as when hiding.
    func beginTransferHold(_ state: inout State) -> Effect<Action> {
        state.isHoldingTransfers = true
        let cancellations: [Effect<Action>] = [.cancel(id: CancelID.thumbnails)]
            + state.deletingItemIDs.map { .cancel(id: CancelID.delete($0)) }
        state.loadingThumbnailIDs = []
        state.deletingItemIDs = []
        state.pendingDeleteItemID = nil
        let expiry = Effect<Action>.run { [clock] send in
            try await clock.sleep(for: Self.backgroundTransferGracePeriod)
            await send(.transferHoldExpired)
        } catch: { _, _ in }
        .cancellable(id: CancelID.transferHold, cancelInFlight: true)
        return .merge(cancellations + [expiry])
    }

    /// Ends the hold once its last held download has finished.
    func reconcileTransferHold(_ state: inout State) -> Effect<Action> {
        guard state.isHoldingTransfers, state.downloadingItemIDs.isEmpty else { return .none }
        return reconcile(&state)
    }

    func stopStream(_ state: inout State) -> Effect<Action> {
        let cancellations = cancelRequests(state)
        state.isStreamRequested = false
        state.isStreaming = false
        state.hasLiveLibrary = false
        state.isHoldingTransfers = false
        clearRequestFlags(&state)
        return .merge(
            cancellations,
            .cancel(id: CancelID.transferHold),
            state.connectionState == .authenticated ? setStreaming(false) : .cancel(id: CancelID.streaming)
        )
    }

    func setStreaming(_ enabled: Bool) -> Effect<Action> {
        .run { [connection] send in
            do {
                try await connection.setScreenshotsStreaming(enabled)
                if enabled { await send(.streamingResponse(.success(true))) }
            } catch is CancellationError {
            } catch let error as RemoteProtocolError {
                if enabled { await send(.streamingResponse(.failure(error))) }
            } catch {
                if enabled { await send(.streamingResponse(.failure(Self.unexpected(error)))) }
            }
        }
        .cancellable(id: CancelID.streaming, cancelInFlight: true)
    }

    /// Requests thumbnails for listed items without one, in batches of at most 12, one effect at a time.
    func fetchMissingThumbnails(_ state: inout State) -> Effect<Action> {
        guard state.isStreaming, state.isHoldingTransfers == false, state.hasLiveLibrary, state.isLibrarySaved,
              let macID = state.selectedMacID, let libraryRevision = state.library?.revision else { return .none }
        let missing = state.items.filter { state.thumbnailURLs[$0.id] == nil }.map(\.id)
        state.loadingThumbnailIDs = Set(missing)
        guard missing.isEmpty == false else { return .cancel(id: CancelID.thumbnails) }
        let generation = state.cacheGeneration
        let batchSize = RemoteScreenshotLimits.maximumThumbnailsPerRequest
        let batches = stride(from: 0, to: missing.count, by: batchSize).map {
            Array(missing[$0..<min($0 + batchSize, missing.count)])
        }
        let requests = batches.map { RemoteScreenshotThumbnailsRequest(requestID: uuid(), ids: $0) }
        return .run { [connection, cache] send in
            for (index, request) in requests.enumerated() {
                do {
                    let result = try await connection.fetchScreenshotThumbnails(.init(macID: macID, request: request))
                    let urls = await cache.saveThumbnails(macID, result.thumbnails)
                    await send(.thumbnailsLoaded(
                        generation: generation,
                        libraryRevision: libraryRevision,
                        urls,
                        failedIDs: request.ids.filter { urls[$0] == nil }
                    ))
                } catch is CancellationError {
                    // Silent: clear what is still loading; the next library or subscription retries.
                    await send(.thumbnailsLoaded(
                        generation: generation,
                        libraryRevision: libraryRevision,
                        [:],
                        failedIDs: requests[index...].flatMap(\.ids)
                    ))
                    return
                } catch {
                    await send(.thumbnailsLoaded(generation: generation, libraryRevision: libraryRevision, [:], failedIDs: request.ids))
                }
            }
        }
        .cancellable(id: CancelID.thumbnails, cancelInFlight: true)
    }

    func download(_ item: RemoteScreenshotItem, intent: Intent, state: inout State) -> Effect<Action> {
        if state.downloadingItemIDs.contains(item.id) {
            if intent == .copy { state.pendingCopyIDs.insert(item.id) }
            return .none
        }
        guard state.isStreaming, let macID = state.selectedMacID else {
            // Viewing offline falls back to the thumbnail; only Copy needs to explain itself.
            if intent == .copy {
                state.operationError = String(localized: "Connect to the Mac to download this screenshot.")
            }
            return .none
        }
        if intent == .copy { state.pendingCopyIDs.insert(item.id) }
        state.downloadingItemIDs.insert(item.id)
        let generation = state.cacheGeneration
        return .run { [images] send in
            do {
                let url = try await images.load(macID, item)
                await send(.imageLoaded(generation: generation, itemID: item.id, url))
            } catch is CancellationError {
                // Superseded by another transfer, unsubscribed or disconnected: retry on demand.
                await send(.imageCancelled(generation: generation, itemID: item.id))
            } catch let error as RemoteProtocolError {
                await send(.imageFailed(generation: generation, itemID: item.id, error))
            } catch {
                await send(.imageFailed(generation: generation, itemID: item.id, Self.unexpected(error)))
            }
        }
        .cancellable(id: CancelID.image(item.id), cancelInFlight: true)
    }

    func copy(_ url: URL, item: RemoteScreenshotItem) -> Effect<Action> {
        .run { [pasteboard] send in
            let copied = await pasteboard.copy(url, item.contentType)
            await send(.copyFinished(item.id, copied))
        }
    }

    /// Cancels in-flight thumbnail, image and delete requests. Their completions are then never
    /// delivered, so callers must clear the matching flags synchronously (`clearRequestFlags`).
    func cancelRequests(_ state: State) -> Effect<Action> {
        .merge(
            [.cancel(id: CancelID.thumbnails)]
                + state.downloadingItemIDs.map { .cancel(id: CancelID.image($0)) }
                + state.deletingItemIDs.map { .cancel(id: CancelID.delete($0)) }
        )
    }

    func cancelWork(_ state: State) -> Effect<Action> {
        .merge(
            cancelRequests(state),
            .cancel(id: CancelID.streaming),
            .cancel(id: CancelID.cacheLoad),
            .cancel(id: CancelID.transferHold)
        )
    }

    func clearRequestFlags(_ state: inout State) {
        state.loadingThumbnailIDs = []
        state.downloadingItemIDs = []
        state.pendingCopyIDs = []
        state.deletingItemIDs = []
        state.pendingDeleteItemID = nil
    }

    func resetTransientState(_ state: inout State, connectionState: DashboardFeature.ConnectionState) -> Effect<Action> {
        let cancellations = cancelWork(state)
        state.connectionState = connectionState
        state.isStreamRequested = false
        state.isStreaming = false
        state.hasLiveLibrary = false
        state.isHoldingTransfers = false
        clearRequestFlags(&state)
        state.availabilityMessage = nil
        state.cacheGeneration &+= 1
        return cancellations
    }

    /// Clears everything tied to the previous Mac; late results for it are dropped by generation.
    func resetForMac(_ macID: UUID?, state: inout State) {
        state.selectedMacID = macID
        state.isStreamRequested = false
        state.isStreaming = false
        state.isHoldingTransfers = false
        state.library = nil
        state.hasLiveLibrary = false
        state.isLibrarySaved = false
        state.thumbnailURLs = [:]
        state.imageURLs = [:]
        clearRequestFlags(&state)
        state.removedItemIDs = []
        state.selectedItemID = nil
        state.copiedItemID = nil
        state.availabilityMessage = nil
        state.operationError = nil
        state.cacheGeneration &+= 1
    }
}

// MARK: - User-facing copy

extension RemoteScreenshotsFeature {
    /// Protocol `message`s are English diagnostics; the user sees localized copy keyed by error code.
    static func availabilityMessage(for error: RemoteProtocolError) -> String {
        switch error.code {
        case .upgradeRequired, .actionNotSupported:
            String(localized: "This Mac needs a newer OnlySwitch version to use Screenshots.")
        case .requestTimedOut:
            String(localized: "The Mac did not respond in time. Try again.")
        default:
            String(localized: "The Mac could not share its screenshots.")
        }
    }

    static func downloadErrorMessage(for error: RemoteProtocolError, isRecording: Bool = false) -> String {
        switch error.code {
        case .controlNotFound:
            String(localized: "This screenshot is no longer on the Mac.")
        case .controlUnavailable where isRecording:
            String(localized: "This item changed on the Mac or is too large to transfer.")
        case .controlUnavailable:
            String(localized: "This screenshot changed on the Mac or is too large to transfer.")
        case .requestTimedOut:
            String(localized: "The Mac did not respond in time. Try again.")
        case .invalidFrame:
            String(localized: "The screenshot transfer was interrupted. Try again.")
        case .authenticationFailed:
            String(localized: "Connect to the Mac to download this screenshot.")
        default:
            String(localized: "The screenshot could not be downloaded.")
        }
    }

    static func deleteErrorMessage(for error: RemoteProtocolError) -> String {
        switch error.code {
        case .controlNotFound:
            String(localized: "This screenshot is no longer on the Mac.")
        case .requestTimedOut:
            String(localized: "The Mac did not respond in time. Try again.")
        case .authenticationFailed:
            String(localized: "Connect to the Mac to delete this screenshot.")
        default:
            String(localized: "The Mac could not move the screenshot to the Trash.")
        }
    }

    /// Non-protocol failures (for example a cache write) get the generic copy for their operation.
    static func unexpected(_ error: any Error) -> RemoteProtocolError {
        RemoteProtocolError(code: .executionFailed, message: String(describing: error))
    }
}
