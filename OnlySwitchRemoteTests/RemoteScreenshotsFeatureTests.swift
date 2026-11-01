import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteScreenshotsFeatureTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
    private let otherMacID = UUID(uuidString: "00000000-0000-0000-0000-00000000E002")!
    private let first = Self.item(0xE101, createdAt: 2)
    private let second = Self.item(0xE102, createdAt: 1)
    private let thumbURL = URL(fileURLWithPath: "/tmp/thumb.jpg")
    private let imageURL = URL(fileURLWithPath: "/tmp/a.png")
    private let otherImageURL = URL(fileURLWithPath: "/tmp/b.png")

    // MARK: Streaming lifecycle

    @Test func visibleEntitledAuthenticatedLoadsCacheThenStreams() async {
        let log = LockIsolated<[String]>([])
        let store = makeStore(authenticated()) {
            $0.remoteScreenshotCache.load = { _ in log.withValue { $0.append("load") }; return nil }
            $0.remoteConnection.setScreenshotsStreaming = { value in log.withValue { $0.append("stream:\(value)") } }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isStreamRequested = true
        }
        await store.receive(.cacheLoaded(generation: 0, nil))
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        #expect(log.value == ["load", "stream:true"])
    }

    @Test func cachedLibraryIsShownBeforeTheLiveOne() async {
        let cached = RemoteScreenshotLibrary(revision: 4, isCollectionEnabled: true, items: [first])
        let store = makeStore(authenticated()) {
            $0.remoteScreenshotCache.load = { _ in
                .init(library: cached, thumbnailURLs: [self.first.id: self.thumbURL], imageURLs: [self.first.id: self.imageURL])
            }
            $0.remoteConnection.setScreenshotsStreaming = { _ in }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isStreamRequested = true
        }
        await store.receive(\.cacheLoaded) {
            $0.library = cached
            $0.thumbnailURLs = [self.first.id: self.thumbURL]
            $0.imageURLs = [self.first.id: self.imageURL]
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        #expect(store.state.isOffline == false)
        #expect(store.state.canDelete == false)
    }

    @Test func notEntitledNeverLoadsOrStreamsUntilEntitled() async {
        let streaming = LockIsolated<[Bool]>([])
        let store = makeStore(authenticated(isEntitled: false)) {
            $0.remoteScreenshotCache.load = { _ in nil }
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
        }

        await store.send(.visibilityChanged(true)) { $0.isVisible = true }
        await store.finish()
        #expect(streaming.value.isEmpty)

        await store.send(.entitlementChanged(true)) {
            $0.isEntitled = true
            $0.isStreamRequested = true
        }
        await store.receive(.cacheLoaded(generation: 0, nil))
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        #expect(streaming.value == [true])
    }

    @Test func hidingStopsStreamingAndCancelsOutstandingWork() async {
        let streaming = LockIsolated<[Bool]>([])
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first, second])
        state.isLibrarySaved = true
        state.thumbnailURLs = [first.id: thumbURL, second.id: thumbURL]
        let store = makeStore(state) {
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
            $0.remoteConnection.deleteScreenshots = { _ in try await Task.never() }
        }

        await store.send(.deleteTapped(second.id)) { $0.pendingDeleteItemID = self.second.id }
        await store.send(.deleteConfirmed) {
            $0.pendingDeleteItemID = nil
            $0.deletingItemIDs = [self.second.id]
        }
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.hasLiveLibrary = false
            $0.deletingItemIDs = []
        }
        await store.finish()
        #expect(streaming.value == [false])
    }

    // MARK: Background transfer hold

    @Test func hidingDuringAnOriginalDownloadKeepsTheSubscriptionUntilItFinishes() async {
        let streaming = LockIsolated<[Bool]>([])
        let clock = TestClock()
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first, second])
        state.isLibrarySaved = true
        state.thumbnailURLs = [second.id: thumbURL]
        state.loadingThumbnailIDs = [first.id]
        let store = makeStore(state) {
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
            $0.remoteConnection.deleteScreenshots = { _ in try await Task.never() }
            $0.remoteScreenshotImages.load = { _, _ in
                try await clock.sleep(for: .seconds(5))
                return self.imageURL
            }
            $0.continuousClock = clock
        }

        await store.send(.dragStarted(first.id)) { $0.downloadingItemIDs = [self.first.id] }
        await store.send(.deleteTapped(second.id)) { $0.pendingDeleteItemID = self.second.id }
        await store.send(.deleteConfirmed) {
            $0.pendingDeleteItemID = nil
            $0.deletingItemIDs = [self.second.id]
        }
        await store.send(.visibilityChanged(false)) {
            // Thumbnails and deletes stop as before; only the original keeps the subscription.
            $0.isVisible = false
            $0.isHoldingTransfers = true
            $0.loadingThumbnailIDs = []
            $0.deletingItemIDs = []
        }
        #expect(streaming.value.isEmpty)

        await clock.advance(by: .seconds(5))
        await store.receive(.imageLoaded(generation: 0, itemID: first.id, imageURL)) {
            $0.downloadingItemIDs = []
            $0.imageURLs = [self.first.id: self.imageURL]
            $0.isHoldingTransfers = false
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.hasLiveLibrary = false
        }
        await store.finish()
        #expect(streaming.value == [false])
    }

    @Test func transferHoldEndsAfterTheGracePeriod() async {
        let streaming = LockIsolated<[Bool]>([])
        let clock = TestClock()
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state) {
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
            $0.remoteScreenshotImages.load = { _, _ in try await Task.never() }
            $0.continuousClock = clock
        }

        await store.send(.copyTapped(first.id)) {
            $0.pendingCopyIDs = [self.first.id]
            $0.downloadingItemIDs = [self.first.id]
        }
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isHoldingTransfers = true
        }
        await clock.advance(by: RemoteScreenshotsFeature.backgroundTransferGracePeriod - .seconds(1))
        #expect(streaming.value.isEmpty)

        await clock.advance(by: .seconds(1))
        await store.receive(.transferHoldExpired) {
            $0.isHoldingTransfers = false
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.hasLiveLibrary = false
            $0.pendingCopyIDs = []
            $0.downloadingItemIDs = []
        }
        await store.finish()
        #expect(streaming.value == [false])
    }

    @Test func failedDownloadEndsTheTransferHold() async {
        let streaming = LockIsolated<[Bool]>([])
        let clock = TestClock()
        let error = RemoteProtocolError(code: .requestTimedOut, message: "x")
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state) {
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
            $0.remoteScreenshotImages.load = { _, _ in
                try await clock.sleep(for: .seconds(1))
                throw error
            }
            $0.continuousClock = clock
        }

        await store.send(.dragStarted(first.id)) { $0.downloadingItemIDs = [self.first.id] }
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isHoldingTransfers = true
        }
        await clock.advance(by: .seconds(1))
        await store.receive(.imageFailed(generation: 0, itemID: first.id, error)) {
            $0.downloadingItemIDs = []
            $0.operationError = "The Mac did not respond in time. Try again."
            $0.isHoldingTransfers = false
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.hasLiveLibrary = false
        }
        await store.finish()
        #expect(streaming.value == [false])
    }

    @Test func returningDuringTheTransferHoldResumesWithoutResubscribing() async {
        let streaming = LockIsolated<[Bool]>([])
        let clock = TestClock()
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first, second])
        state.isLibrarySaved = true
        state.thumbnailURLs = [first.id: thumbURL]
        let store = makeStore(state) {
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
            $0.remoteScreenshotImages.load = { _, _ in
                try await clock.sleep(for: .seconds(5))
                return self.imageURL
            }
            $0.remoteConnection.fetchScreenshotThumbnails = { invocation in
                .init(requestID: invocation.request.requestID, thumbnails: [], missingIDs: invocation.request.ids)
            }
            $0.remoteScreenshotCache.saveThumbnails = { _, _ in [:] }
            $0.continuousClock = clock
        }

        await store.send(.dragStarted(first.id)) { $0.downloadingItemIDs = [self.first.id] }
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isHoldingTransfers = true
        }
        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isHoldingTransfers = false
            $0.loadingThumbnailIDs = [self.second.id]
        }
        await store.receive(.thumbnailsLoaded(generation: 0, libraryRevision: 1, [:], failedIDs: [second.id])) {
            $0.loadingThumbnailIDs = []
        }
        // The grace period no longer applies, and the download completes normally.
        await clock.advance(by: RemoteScreenshotsFeature.backgroundTransferGracePeriod)
        await store.receive(.imageLoaded(generation: 0, itemID: first.id, imageURL)) {
            $0.downloadingItemIDs = []
            $0.imageURLs = [self.first.id: self.imageURL]
        }
        #expect(streaming.value.isEmpty)
    }

    @Test func revocationDuringTheTransferHoldTearsDownImmediately() async {
        let streaming = LockIsolated<[Bool]>([])
        let clock = TestClock()
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state) {
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
            $0.remoteScreenshotImages.load = { _, _ in try await Task.never() }
            $0.continuousClock = clock
        }

        await store.send(.dragStarted(first.id)) { $0.downloadingItemIDs = [self.first.id] }
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isHoldingTransfers = true
        }
        await store.send(.contextChanged(macID: macID, connectionState: .revoked)) {
            $0.connectionState = .revoked
            $0.isHoldingTransfers = false
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.hasLiveLibrary = false
            $0.downloadingItemIDs = []
            $0.cacheGeneration = 1
        }
        await clock.advance(by: RemoteScreenshotsFeature.backgroundTransferGracePeriod)
        await store.finish()
        #expect(streaming.value.isEmpty)
    }

    @Test func changingMacDuringTheTransferHoldTearsDownImmediately() async {
        let clock = TestClock()
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state) {
            $0.remoteScreenshotImages.load = { _, _ in try await Task.never() }
            $0.continuousClock = clock
        }

        await store.send(.dragStarted(first.id)) { $0.downloadingItemIDs = [self.first.id] }
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isHoldingTransfers = true
        }
        await store.send(.contextChanged(macID: otherMacID, connectionState: .offline(nil))) {
            $0.selectedMacID = self.otherMacID
            $0.connectionState = .offline(nil)
            $0.isHoldingTransfers = false
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.library = nil
            $0.hasLiveLibrary = false
            $0.downloadingItemIDs = []
            $0.cacheGeneration = 1
        }
        await clock.advance(by: RemoteScreenshotsFeature.backgroundTransferGracePeriod)
        await store.finish()
    }

    @Test func hidingWithoutAnOriginalDownloadDoesNotHold() async {
        let streaming = LockIsolated<[Bool]>([])
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.imageURLs = [first.id: imageURL]
        let store = makeStore(state) {
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
        }

        // A cached original needs no download, so dragging it starts nothing.
        await store.send(.dragStarted(first.id))
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.hasLiveLibrary = false
        }
        await store.finish()
        #expect(streaming.value == [false])
    }

    @Test func oldMacShowsUpgradeMessage() async {
        let store = makeStore(authenticated()) {
            $0.remoteScreenshotCache.load = { _ in nil }
            $0.remoteConnection.setScreenshotsStreaming = { _ in
                throw RemoteProtocolError(code: .upgradeRequired, message: "x")
            }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
            $0.isStreamRequested = true
        }
        await store.receive(.cacheLoaded(generation: 0, nil))
        await store.receive(.streamingResponse(.failure(.init(code: .upgradeRequired, message: "x")))) {
            $0.availabilityMessage = "This Mac needs a newer OnlySwitch version to use Screenshots."
        }
    }

    // MARK: Library and thumbnails

    @Test func libraryIsSavedBeforeThumbnailsAreRequestedInBatches() async {
        let items = (0..<14).map { Self.item(0xF000 + $0, createdAt: Double($0)) }
        let library = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: items)
        let log = LockIsolated<[String]>([])
        let requested = LockIsolated<[[UUID]]>([])
        let cachedThumb = [items[0].id: thumbURL]
        let store = makeStore(streamingState()) {
            $0.remoteScreenshotCache.replaceLibrary = { _, received in
                log.withValue { $0.append("save:\(received.revision)") }
                return .init(library: received, thumbnailURLs: cachedThumb, imageURLs: [:])
            }
            $0.remoteConnection.fetchScreenshotThumbnails = { invocation in
                log.withValue { $0.append("fetch") }
                #expect(invocation.macID == self.macID)
                requested.withValue { $0.append(invocation.request.ids) }
                return .init(requestID: invocation.request.requestID, thumbnails: [], missingIDs: invocation.request.ids)
            }
            $0.remoteScreenshotCache.saveThumbnails = { _, _ in [:] }
        }

        await store.send(.connectionEvent(.screenshots(macID, library))) {
            $0.library = library
            $0.hasLiveLibrary = true
            $0.isSavingLibrary = true
        }
        await store.receive(\.libraryCached) {
            $0.isSavingLibrary = false
            $0.isLibrarySaved = true
            $0.thumbnailURLs = cachedThumb
            $0.loadingThumbnailIDs = Set(items.dropFirst().map(\.id))
        }
        let firstBatch = Array(items[1...12].map(\.id))
        let secondBatch = [items[13].id]
        await store.receive(.thumbnailsLoaded(generation: 0, libraryRevision: 1, [:], failedIDs: firstBatch)) {
            $0.loadingThumbnailIDs = Set(secondBatch)
        }
        await store.receive(.thumbnailsLoaded(generation: 0, libraryRevision: 1, [:], failedIDs: secondBatch)) {
            $0.loadingThumbnailIDs = []
        }
        #expect(requested.value == [firstBatch, secondBatch])
        #expect(log.value == ["save:1", "fetch", "fetch"])
    }

    @Test func receivedThumbnailsAreStored() async {
        let library = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [first, second])
        let store = makeStore(streamingState()) {
            $0.remoteScreenshotCache.replaceLibrary = { _, received in
                .init(library: received, thumbnailURLs: [self.second.id: self.thumbURL], imageURLs: [:])
            }
            $0.remoteConnection.fetchScreenshotThumbnails = { invocation in
                .init(
                    requestID: invocation.request.requestID,
                    thumbnails: [try .init(itemID: self.first.id, revision: 0, jpegData: Data([1]))],
                    missingIDs: []
                )
            }
            $0.remoteScreenshotCache.saveThumbnails = { macID, thumbnails in
                #expect(macID == self.macID)
                #expect(thumbnails.map(\.itemID) == [self.first.id])
                return [self.first.id: self.thumbURL]
            }
        }

        await store.send(.connectionEvent(.screenshots(macID, library))) {
            $0.library = library
            $0.hasLiveLibrary = true
            $0.isSavingLibrary = true
        }
        await store.receive(\.libraryCached) {
            $0.isSavingLibrary = false
            $0.isLibrarySaved = true
            $0.thumbnailURLs = [self.second.id: self.thumbURL]
            $0.loadingThumbnailIDs = [self.first.id]
        }
        await store.receive(\.thumbnailsLoaded) {
            $0.thumbnailURLs = [self.first.id: self.thumbURL, self.second.id: self.thumbURL]
            $0.loadingThumbnailIDs = []
        }
    }

    @Test func libraryArrivingBeforeSubscriptionReplyFetchesThumbnailsOnceStreaming() async {
        var state = streamingState()
        state.isStreaming = false
        let library = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [first])
        let requested = LockIsolated<[[UUID]]>([])
        let store = makeStore(state) {
            $0.remoteScreenshotCache.replaceLibrary = { _, received in .init(library: received, thumbnailURLs: [:], imageURLs: [:]) }
            $0.remoteConnection.fetchScreenshotThumbnails = { invocation in
                requested.withValue { $0.append(invocation.request.ids) }
                return .init(requestID: invocation.request.requestID, thumbnails: [], missingIDs: invocation.request.ids)
            }
            $0.remoteScreenshotCache.saveThumbnails = { _, _ in [:] }
        }

        await store.send(.connectionEvent(.screenshots(macID, library))) {
            $0.library = library
            $0.hasLiveLibrary = true
            $0.isSavingLibrary = true
        }
        await store.receive(\.libraryCached) {
            $0.isSavingLibrary = false
            $0.isLibrarySaved = true
        }
        #expect(requested.value.isEmpty)

        await store.send(.streamingResponse(.success(true))) {
            $0.isStreaming = true
            $0.loadingThumbnailIDs = [self.first.id]
        }
        await store.receive(\.thumbnailsLoaded) { $0.loadingThumbnailIDs = [] }
        #expect(requested.value == [[first.id]])
    }

    @Test func librarySavesAreSerializedAndOnlyUseReceivedLibraries() async {
        let older = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [first, second])
        let newer = RemoteScreenshotLibrary(revision: 2, isCollectionEnabled: true, items: [second])
        let (gate, open) = AsyncStream<Void>.makeStream()
        let saved = LockIsolated<[UInt64]>([])
        let store = makeStore(streamingState()) {
            $0.remoteScreenshotCache.replaceLibrary = { _, received in
                saved.withValue { $0.append(received.revision) }
                if received.revision == 1 { for await _ in gate { break } }
                return .init(library: received, thumbnailURLs: [self.second.id: self.thumbURL], imageURLs: [:])
            }
        }

        await store.send(.connectionEvent(.screenshots(macID, older))) {
            $0.library = older
            $0.hasLiveLibrary = true
            $0.isSavingLibrary = true
        }
        await store.send(.connectionEvent(.screenshots(macID, newer))) { $0.library = newer }
        open.yield()
        // The older save finishes, is not applied, and the current library is saved next.
        await store.receive(.libraryCached(generation: 0, .init(library: older, thumbnailURLs: [second.id: thumbURL], imageURLs: [:])))
        await store.receive(.libraryCached(generation: 0, .init(library: newer, thumbnailURLs: [second.id: thumbURL], imageURLs: [:]))) {
            $0.isSavingLibrary = false
            $0.isLibrarySaved = true
            $0.thumbnailURLs = [self.second.id: self.thumbURL]
        }
        #expect(saved.value == [1, 2])
    }

    @Test func librariesForOtherMacsWithoutRequestOrOlderRevisionAreIgnored() async {
        var state = authenticated()
        state.isVisible = true
        let store = makeStore(state)
        let library = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [first])

        await store.send(.connectionEvent(.screenshots(otherMacID, library)))
        await store.send(.connectionEvent(.screenshots(macID, library)))

        var live = streamingState()
        live.library = .init(revision: 5, isCollectionEnabled: true, items: [second])
        live.isLibrarySaved = true
        let liveStore = makeStore(live)
        await liveStore.send(.connectionEvent(.screenshots(macID, library)))
    }

    @Test func staleThumbnailResultsAreDropped() async {
        var state = streamingState()
        state.cacheGeneration = 3
        state.library = .init(revision: 7, isCollectionEnabled: true, items: [first])
        state.loadingThumbnailIDs = [first.id]
        let store = makeStore(state)

        await store.send(.thumbnailsLoaded(generation: 2, libraryRevision: 7, [first.id: thumbURL], failedIDs: []))
        await store.send(.thumbnailsLoaded(generation: 3, libraryRevision: 6, [first.id: thumbURL], failedIDs: []))
    }

    @Test func thumbnailTransportCancellationIsSilent() async {
        let library = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(streamingState()) {
            $0.remoteScreenshotCache.replaceLibrary = { _, received in .init(library: received, thumbnailURLs: [:], imageURLs: [:]) }
            $0.remoteConnection.fetchScreenshotThumbnails = { _ in throw CancellationError() }
        }

        await store.send(.connectionEvent(.screenshots(macID, library))) {
            $0.library = library
            $0.hasLiveLibrary = true
            $0.isSavingLibrary = true
        }
        await store.receive(\.libraryCached) {
            $0.isSavingLibrary = false
            $0.isLibrarySaved = true
            $0.loadingThumbnailIDs = [self.first.id]
        }
        await store.receive(.thumbnailsLoaded(generation: 0, libraryRevision: 1, [:], failedIDs: [first.id])) {
            $0.loadingThumbnailIDs = []
        }
    }

    // MARK: Copy and download

    @Test func copyDownloadsThenCopiesOnTheMainActorWithFeedback() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let clock = TestClock()
        let copies = LockIsolated<[URL]>([])
        let store = makeStore(state) {
            $0.remoteScreenshotImages.load = { macID, item in
                #expect(macID == self.macID)
                #expect(item == self.first)
                return self.imageURL
            }
            $0.remoteScreenshotPasteboard.copy = { url, type in
                MainActor.assertIsolated()
                copies.withValue { $0.append(url) }
                return type == "public.png"
            }
            $0.continuousClock = clock
        }

        await store.send(.copyTapped(first.id)) {
            $0.pendingCopyIDs = [self.first.id]
            $0.downloadingItemIDs = [self.first.id]
        }
        await store.receive(.imageLoaded(generation: 0, itemID: first.id, imageURL)) {
            $0.pendingCopyIDs = []
            $0.downloadingItemIDs = []
            $0.imageURLs = [self.first.id: self.imageURL]
        }
        await store.receive(.copyFinished(first.id, true)) { $0.copiedItemID = self.first.id }
        await clock.advance(by: RemoteScreenshotsFeature.copyFeedbackDuration)
        await store.receive(.copyFeedbackExpired(first.id)) { $0.copiedItemID = nil }
        #expect(copies.value == [imageURL])
    }

    @Test func copyUsesCachedOriginalWithoutDownloading() async {
        var state = authenticated()
        state.connectionState = .offline(nil)
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.imageURLs = [first.id: imageURL]
        let clock = TestClock()
        let store = makeStore(state) {
            $0.remoteScreenshotPasteboard.copy = { _, _ in true }
            $0.continuousClock = clock
        }

        await store.send(.copyTapped(first.id))
        await store.receive(.copyFinished(first.id, true)) { $0.copiedItemID = self.first.id }
        await clock.advance(by: RemoteScreenshotsFeature.copyFeedbackDuration)
        await store.receive(.copyFeedbackExpired(first.id)) { $0.copiedItemID = nil }
    }

    @Test func copyFailureShowsError() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.imageURLs = [first.id: imageURL]
        let store = makeStore(state) {
            $0.remoteScreenshotPasteboard.copy = { _, _ in false }
        }

        await store.send(.copyTapped(first.id))
        await store.receive(.copyFinished(first.id, false)) {
            $0.operationError = "The screenshot could not be copied."
        }
        await store.send(.errorDismissed) { $0.operationError = nil }
    }

    @Test func copyWhileOfflineWithoutCachedOriginalShowsError() async {
        var state = authenticated()
        state.connectionState = .offline(nil)
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state)

        await store.send(.copyTapped(first.id)) {
            $0.operationError = "Connect to the Mac to download this screenshot."
        }
    }

    @Test func viewingOfflineWithoutCachedOriginalOnlySelects() async {
        var state = authenticated()
        state.connectionState = .offline(nil)
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state)

        await store.send(.itemTapped(first.id)) { $0.selectedItemID = self.first.id }
        await store.send(.detailDismissed) { $0.selectedItemID = nil }
    }

    @Test func viewingDownloadsWithoutCopying() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state) {
            $0.remoteScreenshotImages.load = { _, _ in self.imageURL }
        }

        await store.send(.itemTapped(first.id)) {
            $0.selectedItemID = self.first.id
            $0.downloadingItemIDs = [self.first.id]
        }
        await store.receive(.imageLoaded(generation: 0, itemID: first.id, imageURL)) {
            $0.downloadingItemIDs = []
            $0.imageURLs = [self.first.id: self.imageURL]
        }
    }

    @Test func supersededDownloadIsSilentAndCanBeRetried() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first, second])
        let attempts = LockIsolated(0)
        let store = makeStore(state) {
            $0.remoteScreenshotImages.load = { _, item in
                if item.id == self.second.id { return self.otherImageURL }
                // The first attempt is superseded by another transfer; the retry succeeds.
                let attempt = attempts.withValue { $0 += 1; return $0 }
                if attempt == 1 { throw CancellationError() }
                return self.imageURL
            }
            $0.remoteScreenshotPasteboard.copy = { _, _ in true }
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.copyTapped(first.id)) {
            $0.pendingCopyIDs = [self.first.id]
            $0.downloadingItemIDs = [self.first.id]
        }
        await store.receive(.imageCancelled(generation: 0, itemID: first.id)) {
            $0.pendingCopyIDs = []
            $0.downloadingItemIDs = []
        }
        await store.send(.itemTapped(second.id)) {
            $0.selectedItemID = self.second.id
            $0.downloadingItemIDs = [self.second.id]
        }
        await store.receive(.imageLoaded(generation: 0, itemID: second.id, otherImageURL)) {
            $0.downloadingItemIDs = []
            $0.imageURLs = [self.second.id: self.otherImageURL]
        }
        await store.send(.copyTapped(first.id)) {
            $0.pendingCopyIDs = [self.first.id]
            $0.downloadingItemIDs = [self.first.id]
        }
        await store.receive(.imageLoaded(generation: 0, itemID: first.id, imageURL)) {
            $0.pendingCopyIDs = []
            $0.downloadingItemIDs = []
            $0.imageURLs[self.first.id] = self.imageURL
        }
        await store.receive(.copyFinished(first.id, true)) { $0.copiedItemID = self.first.id }
        await store.receive(.copyFeedbackExpired(first.id)) { $0.copiedItemID = nil }
        #expect(store.state.operationError == nil)
    }

    @Test(arguments: [
        (RemoteProtocolError.Code.controlNotFound, "This screenshot is no longer on the Mac."),
        (.controlUnavailable, "This screenshot changed on the Mac or is too large to transfer."),
        (.requestTimedOut, "The Mac did not respond in time. Try again."),
        (.invalidFrame, "The screenshot transfer was interrupted. Try again."),
        (.authenticationFailed, "Connect to the Mac to download this screenshot."),
        (.executionFailed, "The screenshot could not be downloaded."),
        (.actionNotSupported, "The screenshot could not be downloaded."),
    ])
    func downloadErrorsUseLocalizedCopyForTheirCode(code: RemoteProtocolError.Code, message: String) async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let error = RemoteProtocolError(code: code, message: "English diagnostic")
        let store = makeStore(state) {
            $0.remoteScreenshotImages.load = { _, _ in throw error }
        }

        await store.send(.copyTapped(first.id)) {
            $0.pendingCopyIDs = [self.first.id]
            $0.downloadingItemIDs = [self.first.id]
        }
        await store.receive(.imageFailed(generation: 0, itemID: first.id, error)) {
            $0.pendingCopyIDs = []
            $0.downloadingItemIDs = []
            $0.operationError = message
        }
    }

    @Test func nonProtocolDownloadErrorUsesGenericCopy() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state) {
            $0.remoteScreenshotImages.load = { _, _ in throw RemoteScreenshotCacheError.pathOutsideCache }
        }

        await store.send(.itemTapped(first.id)) {
            $0.selectedItemID = self.first.id
            $0.downloadingItemIDs = [self.first.id]
        }
        await store.receive(\.imageFailed) {
            $0.downloadingItemIDs = []
            $0.operationError = "The screenshot could not be downloaded."
        }
    }

    // MARK: Drag

    @Test func becomingVisibleHandsTheReducersImageClientToDragProviders() async throws {
        let loads = LockIsolated<[UUID]>([])
        let expectedMac = macID
        let store = makeStore(authenticated(isEntitled: false)) {
            $0.remoteScreenshotImages = RemoteScreenshotImageClient { mac, item in
                #expect(mac == expectedMac)
                loads.withValue { $0.append(item.id) }
                return self.imageURL
            }
        }
        await #expect(throws: RemoteDependencyError.self) {
            try await store.state.dragImages.client.load(self.macID, self.first)
        }

        await store.send(.visibilityChanged(true)) { $0.isVisible = true }

        #expect(try await store.state.dragImages.client.load(macID, first) == imageURL)
        #expect(loads.value == [first.id])
    }

    @Test func dragStartDownloadsAnUncachedOriginalWithoutCopyingOrOpening() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state) {
            $0.remoteScreenshotImages.load = { macID, item in
                #expect(macID == self.macID)
                #expect(item == self.first)
                return self.imageURL
            }
        }

        await store.send(.dragStarted(first.id)) { $0.downloadingItemIDs = [self.first.id] }
        await store.receive(.imageLoaded(generation: 0, itemID: first.id, imageURL)) {
            $0.downloadingItemIDs = []
            $0.imageURLs = [self.first.id: self.imageURL]
        }
        #expect(store.state.selectedItemID == nil)
        #expect(store.state.copiedItemID == nil)
    }

    @Test func dragStartWhileDownloadingOrOfflineStartsNothing() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first, second])
        state.downloadingItemIDs = [first.id]
        let store = makeStore(state)

        await store.send(.dragStarted(first.id))
        await store.send(.dragStarted(UUID()))
        await store.send(.contextChanged(macID: macID, connectionState: .offline(nil))) {
            $0.connectionState = .offline(nil)
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.hasLiveLibrary = false
            $0.downloadingItemIDs = []
            $0.cacheGeneration = 1
        }
        // Offline, the drop simply fails; no alert interrupts the drag.
        await store.send(.dragStarted(second.id))
        #expect(store.state.operationError == nil)
    }

    @Test func dragStartAndTheDragProviderShareOneDownload() async throws {
        let fetches = LockIsolated(0)
        let saved = LockIsolated<URL?>(nil)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let cache = RemoteScreenshotCacheClient(
            load: { _ in nil },
            replaceLibrary: { _, library in .init(library: library, thumbnailURLs: [:], imageURLs: [:]) },
            saveThumbnails: { _, _ in [:] },
            imageURL: { _, _ in saved.value },
            saveImage: { _, _, _ in saved.withValue { $0 = self.imageURL }; return self.imageURL },
            removeMac: { _ in }
        )
        let images = RemoteScreenshotImageClient.live(
            cache: cache,
            fetchImage: { _ in
                fetches.withValue { $0 += 1 }
                for await _ in release { break }
                return .init(contentType: "public.png", data: Data([1, 2, 3]))
            },
            makeRequestID: { UUID() }
        )
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.dragImages = .init(client: images)
        let store = makeStore(state) { $0.remoteScreenshotImages = images }

        await store.send(.dragStarted(first.id)) { $0.downloadingItemIDs = [self.first.id] }
        let drop = Task { try await store.state.dragImages.client.load(self.macID, self.first) }
        while fetches.value == 0 { await Task.yield() }
        releaseContinuation.yield()
        releaseContinuation.finish()
        await store.receive(.imageLoaded(generation: 0, itemID: first.id, imageURL)) {
            $0.downloadingItemIDs = []
            $0.imageURLs = [self.first.id: self.imageURL]
        }
        #expect(try await drop.value == imageURL)
        #expect(fetches.value == 1)
    }

    // MARK: Delete

    @Test func deleteRequiresConfirmationAndHidesItemUntilNextLibrary() async {
        var state = streamingState()
        let library = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [first, second])
        state.library = library
        state.isLibrarySaved = true
        state.thumbnailURLs = [first.id: thumbURL, second.id: thumbURL]
        state.selectedItemID = first.id
        let deleted = LockIsolated<[[UUID]]>([])
        let saved = LockIsolated<[RemoteScreenshotLibrary]>([])
        let store = makeStore(state) {
            $0.remoteConnection.deleteScreenshots = { invocation in
                #expect(invocation.macID == self.macID)
                deleted.withValue { $0.append(invocation.request.ids) }
                return .init(requestID: invocation.request.requestID, failedIDs: [])
            }
            $0.remoteScreenshotCache.replaceLibrary = { _, received in
                saved.withValue { $0.append(received) }
                return .init(library: received, thumbnailURLs: [self.second.id: self.thumbURL], imageURLs: [:])
            }
        }

        await store.send(.deleteTapped(first.id)) { $0.pendingDeleteItemID = self.first.id }
        await store.send(.deleteCancelled) { $0.pendingDeleteItemID = nil }
        await store.send(.deleteTapped(first.id)) { $0.pendingDeleteItemID = self.first.id }
        await store.send(.deleteConfirmed) {
            $0.pendingDeleteItemID = nil
            $0.deletingItemIDs = [self.first.id]
            $0.selectedItemID = nil
        }
        await store.receive(\.deleteResponse) {
            $0.deletingItemIDs = []
            $0.removedItemIDs = [self.first.id]
        }
        #expect(deleted.value == [[first.id]])
        #expect(store.state.items == [second])
        #expect(store.state.library == library)
        #expect(saved.value.isEmpty)

        let synced = RemoteScreenshotLibrary(revision: 2, isCollectionEnabled: true, items: [second])
        await store.send(.connectionEvent(.screenshots(macID, synced))) {
            $0.library = synced
            $0.removedItemIDs = []
            $0.isLibrarySaved = false
            $0.isSavingLibrary = true
        }
        await store.receive(\.libraryCached) {
            $0.isSavingLibrary = false
            $0.isLibrarySaved = true
            $0.thumbnailURLs = [self.second.id: self.thumbURL]
        }
        #expect(saved.value == [synced])
    }

    @Test func deleteReportedAsFailedShowsError() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.pendingDeleteItemID = first.id
        let store = makeStore(state) {
            $0.remoteConnection.deleteScreenshots = { .init(requestID: $0.request.requestID, failedIDs: [self.first.id]) }
        }

        await store.send(.deleteConfirmed) {
            $0.pendingDeleteItemID = nil
            $0.deletingItemIDs = [self.first.id]
        }
        await store.receive(\.deleteResponse) {
            $0.deletingItemIDs = []
            $0.operationError = "The Mac could not move the screenshot to the Trash."
        }
    }

    @Test func deleteTimeoutShowsTimeoutCopy() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.pendingDeleteItemID = first.id
        let store = makeStore(state) {
            $0.remoteConnection.deleteScreenshots = { _ in throw RemoteProtocolError(code: .requestTimedOut, message: "x") }
        }

        await store.send(.deleteConfirmed) {
            $0.pendingDeleteItemID = nil
            $0.deletingItemIDs = [self.first.id]
        }
        await store.receive(\.deleteResponse) {
            $0.deletingItemIDs = []
            $0.operationError = "The Mac did not respond in time. Try again."
        }
    }

    @Test func deleteCancellationIsSilent() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.pendingDeleteItemID = first.id
        let store = makeStore(state) {
            $0.remoteConnection.deleteScreenshots = { _ in throw CancellationError() }
        }

        await store.send(.deleteConfirmed) {
            $0.pendingDeleteItemID = nil
            $0.deletingItemIDs = [self.first.id]
        }
        await store.receive(.deleteInterrupted(generation: 0, first.id)) { $0.deletingItemIDs = [] }
    }

    @Test func deleteIsIgnoredOfflineOrWithoutLiveLibrary() async {
        var state = authenticated()
        state.connectionState = .offline(nil)
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state)
        await store.send(.deleteTapped(first.id))

        var cachedOnly = streamingState()
        cachedOnly.hasLiveLibrary = false
        cachedOnly.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let cachedStore = makeStore(cachedOnly)
        await cachedStore.send(.deleteTapped(first.id))
    }

    // MARK: Connection and Mac changes

    @Test func goingOfflineKeepsCachedLibraryButDropsTransientState() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.isLibrarySaved = true
        state.thumbnailURLs = [first.id: thumbURL]
        state.downloadingItemIDs = [first.id]
        state.pendingCopyIDs = [first.id]
        state.pendingDeleteItemID = first.id
        let store = makeStore(state)

        await store.send(.connectionEvent(.offline(macID, nil))) {
            $0.connectionState = .offline(nil)
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.hasLiveLibrary = false
            $0.downloadingItemIDs = []
            $0.pendingCopyIDs = []
            $0.pendingDeleteItemID = nil
            $0.cacheGeneration = 1
        }
        #expect(store.state.isOffline)
        #expect(store.state.items == [first])
    }

    @Test func reconnectingResubscribes() async {
        var state = authenticated()
        state.connectionState = .offline(nil)
        state.isVisible = true
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state) {
            $0.remoteConnection.setScreenshotsStreaming = { _ in }
        }

        await store.send(.connectionEvent(.connecting(macID))) {
            $0.connectionState = .connecting
            $0.cacheGeneration = 1
        }
        await store.send(.connectionEvent(.authenticated(macID))) {
            $0.connectionState = .authenticated
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
    }

    @Test func selectingAnotherMacResetsStateAndLoadsItsCache() async {
        var state = streamingState()
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        state.isLibrarySaved = true
        state.thumbnailURLs = [first.id: thumbURL]
        state.imageURLs = [first.id: imageURL]
        state.selectedItemID = first.id
        state.removedItemIDs = [second.id]
        state.operationError = "x"
        let otherLibrary = RemoteScreenshotLibrary(revision: 9, isCollectionEnabled: false, items: [second])
        let streaming = LockIsolated<[Bool]>([])
        let store = makeStore(state) {
            $0.remoteScreenshotCache.load = { id in
                #expect(id == self.otherMacID)
                return .init(library: otherLibrary, thumbnailURLs: [:], imageURLs: [:])
            }
            $0.remoteConnection.setScreenshotsStreaming = { value in streaming.withValue { $0.append(value) } }
        }

        await store.send(.contextChanged(macID: otherMacID, connectionState: .offline(nil))) {
            $0.selectedMacID = self.otherMacID
            $0.connectionState = .offline(nil)
            $0.library = nil
            $0.hasLiveLibrary = false
            $0.isLibrarySaved = false
            $0.thumbnailURLs = [:]
            $0.imageURLs = [:]
            $0.selectedItemID = nil
            $0.removedItemIDs = []
            $0.operationError = nil
            $0.isStreamRequested = false
            $0.isStreaming = false
            $0.cacheGeneration = 1
        }
        await store.receive(.cacheLoaded(generation: 1, .init(library: otherLibrary, thumbnailURLs: [:], imageURLs: [:]))) {
            $0.library = otherLibrary
        }
        await store.send(.contextChanged(macID: otherMacID, connectionState: .offline(nil)))
        #expect(streaming.value.isEmpty)

        await store.send(.contextChanged(macID: otherMacID, connectionState: .authenticated)) {
            $0.connectionState = .authenticated
            $0.isStreamRequested = true
        }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        #expect(streaming.value == [true])
    }

    @Test func staleGenerationResultsAreDropped() async {
        var state = streamingState()
        state.cacheGeneration = 3
        state.library = .init(revision: 1, isCollectionEnabled: true, items: [first])
        let store = makeStore(state)
        let snapshot = RemoteScreenshotCacheSnapshot(library: .init(revision: 1, isCollectionEnabled: true, items: [second]), thumbnailURLs: [:], imageURLs: [:])

        await store.send(.cacheLoaded(generation: 2, snapshot))
        await store.send(.imageLoaded(generation: 2, itemID: first.id, imageURL))
        await store.send(.imageFailed(generation: 2, itemID: first.id, .init(code: .requestTimedOut, message: "")))
        await store.send(.deleteResponse(generation: 2, first.id, .success(.init(requestID: UUID(), failedIDs: []))))
        await store.send(.deleteResponse(generation: 2, first.id, .failure(.init(code: .requestTimedOut, message: ""))))
    }

    @Test func cacheLoadIsIgnoredOnceTheLiveLibraryArrived() async {
        var state = streamingState()
        state.library = .init(revision: 2, isCollectionEnabled: true, items: [first])
        let store = makeStore(state)
        await store.send(.cacheLoaded(generation: 0, .init(library: .init(revision: 1, isCollectionEnabled: true, items: [second]), thumbnailURLs: [:], imageURLs: [:])))
    }

    // MARK: Helpers

    private static func item(_ suffix: Int, createdAt: Double) -> RemoteScreenshotItem {
        RemoteScreenshotItem(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", suffix))!,
            fileName: "\(suffix).png",
            contentType: "public.png",
            createdAt: .init(timeIntervalSince1970: createdAt),
            isPinned: false,
            revision: 0,
            byteCount: 3
        )
    }

    private func authenticated(isEntitled: Bool = true) -> RemoteScreenshotsFeature.State {
        var state = RemoteScreenshotsFeature.State()
        state.selectedMacID = macID
        state.connectionState = .authenticated
        state.isEntitled = isEntitled
        return state
    }

    private func streamingState() -> RemoteScreenshotsFeature.State {
        var state = authenticated()
        state.isVisible = true
        state.isStreamRequested = true
        state.isStreaming = true
        state.hasLiveLibrary = true
        return state
    }

    /// Every screenshot dependency fails loudly unless a test overrides it.
    private func makeStore(
        _ state: RemoteScreenshotsFeature.State,
        dependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<RemoteScreenshotsFeature> {
        TestStore(initialState: state) { RemoteScreenshotsFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.remoteScreenshotCache = RemoteScreenshotCacheClient(
                load: { _ in Issue.record("unexpected cache load"); return nil },
                replaceLibrary: { _, library in
                    Issue.record("unexpected library save")
                    return .init(library: library, thumbnailURLs: [:], imageURLs: [:])
                },
                saveThumbnails: { _, _ in Issue.record("unexpected thumbnail save"); return [:] },
                imageURL: { _, _ in Issue.record("unexpected image lookup"); return nil },
                saveImage: { _, _, _ in throw RemoteDependencyError.unimplemented },
                removeMac: { _ in Issue.record("unexpected cache removal") }
            )
            $0.remoteScreenshotImages = RemoteScreenshotImageClient { _, _ in
                Issue.record("unexpected image load")
                throw RemoteDependencyError.unimplemented
            }
            $0.remoteScreenshotPasteboard = RemoteScreenshotPasteboardClient { _, _ in
                Issue.record("unexpected copy")
                return false
            }
            dependencies(&$0)
        }
    }
}
