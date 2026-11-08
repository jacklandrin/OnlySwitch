import ComposableArchitecture
import Foundation
import RemoteCore

// MARK: - Effects

extension RemoteScreenshotsFeature {
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
