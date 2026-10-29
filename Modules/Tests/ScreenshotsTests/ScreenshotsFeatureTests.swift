#if os(macOS)
import ComposableArchitecture
import Foundation
import Testing
@testable import Screenshots

/// Records every client/presentation call; no test touches the pasteboard, NSWorkspace, user folders or the
/// real `com.apple.screencapture` domain.
final class ScreenshotsCallRecorder: Sendable {
    let loads = LockIsolated(0)
    let pins = LockIsolated<[(UUID, Bool)]>([])
    let trashed = LockIsolated<[[UUID]]>([])
    let copied = LockIsolated<[URL]>([])
    let opened = LockIsolated<[URL]>([])
    let reveals = LockIsolated(0)
    let flights = LockIsolated<[(URL, CGRect)]>([])
    let editors = LockIsolated<[UUID]>([])
    let toggles = LockIsolated<[Bool]>([])
    let folderReveals = LockIsolated(0)
}

func screenshotURL(_ id: UUID) -> URL { URL(fileURLWithPath: "/OnlySwitchFixture/\(id.uuidString).png") }

extension ScreenshotsClient {
    static func fixture(
        _ recorder: ScreenshotsCallRecorder,
        known: [ScreenshotItem] = [],
        load: @escaping @Sendable () async throws -> [ScreenshotItem] = { [] },
        captures: @escaping @Sendable () -> AsyncStream<ScreenshotItem> = { AsyncStream { $0.finish() } },
        trash: (@Sendable ([UUID]) async -> (items: [ScreenshotItem], failures: [ScreenshotFailure]))? = nil,
        captureStatus: @escaping @Sendable () async -> ScreenshotCaptureStatus = { .disabled },
        enableCapture: @escaping @Sendable () async throws -> Void = {},
        copyResult: Bool = true
    ) -> Self {
        let knownIDs = Set(known.map(\.id))
        return Self(
            folderURL: { URL(fileURLWithPath: "/OnlySwitchFixture") },
            load: { recorder.loads.withValue { $0 += 1 }; return try await load() },
            captures: captures,
            setPinned: { id, pinned in
                recorder.pins.withValue { $0.append((id, pinned)) }
                return known.map { var item = $0; if item.id == id { item.isPinned = pinned }; return item }.displayOrdered()
            },
            trash: { ids in
                recorder.trashed.withValue { $0.append(ids) }
                if let trash { return await trash(ids) }
                return (items: known.filter { !ids.contains($0.id) }.displayOrdered(), failures: [])
            },
            replaceImage: { _, _ in known },
            fileURL: { id in knownIDs.contains(id) ? screenshotURL(id) : nil },
            thumbnail: { _, _, _ in nil },
            captureStatus: captureStatus,
            enableCapture: { recorder.toggles.withValue { $0.append(true) }; try await enableCapture() },
            disableCapture: { recorder.toggles.withValue { $0.append(false) } },
            copyToPasteboard: { url in recorder.copied.withValue { $0.append(url) }; return copyResult },
            openInDefaultApp: { url in recorder.opened.withValue { $0.append(url) } },
            revealFolder: { recorder.folderReveals.withValue { $0 += 1 } }
        )
    }
}

extension ScreenshotPresentationClient {
    static func fixture(_ recorder: ScreenshotsCallRecorder, reveals: Bool = true, reduceMotion: Bool = false) -> Self {
        Self(
            revealScreenshotsSection: { recorder.reveals.withValue { $0 += 1 }; return reveals },
            flyIn: { url, frame in recorder.flights.withValue { $0.append((url, frame)) } },
            openEditor: { id in recorder.editors.withValue { $0.append(id) } },
            reduceMotion: { reduceMotion }
        )
    }
}

@MainActor
struct ScreenshotsFeatureTests {
    let older = item(createdAt: 10)
    let newer = item(createdAt: 20)
    let pinned = item(createdAt: 5, pinned: true)
    let frame = CGRect(x: 100, y: 200, width: 136, height: 85)

    func started(_ items: [ScreenshotItem], incoming: UUID? = nil, status: ScreenshotCaptureStatus = .active) -> ScreenshotsFeature.State {
        var state = ScreenshotsFeature.State()
        state.items = items.displayOrdered()
        state.fileURLs = Dictionary(uniqueKeysWithValues: items.map { ($0.id, screenshotURL($0.id)) })
        state.incomingItemID = incoming
        state.captureStatus = status
        state.hasStarted = true
        return state
    }

    func makeStore(_ state: ScreenshotsFeature.State, client: ScreenshotsClient, presentation: ScreenshotPresentationClient, clock: TestClock<Duration> = TestClock()) -> TestStoreOf<ScreenshotsFeature> {
        TestStore(initialState: state) { ScreenshotsFeature() } withDependencies: {
            $0.screenshotsClient = client
            $0.screenshotPresentationClient = presentation
            $0.continuousClock = clock
        }
    }

    // MARK: - Lifecycle

    @Test func taskLoadsLibraryOnceAndSubscribesToCaptures() async {
        let recorder = ScreenshotsCallRecorder(), clock = TestClock()
        let (stream, continuation) = AsyncStream.makeStream(of: ScreenshotItem.self)
        let captured = item(createdAt: 30)
        let loaded = [older, newer]
        let store = makeStore(.init(), client: .fixture(recorder, known: loaded + [captured], load: { loaded }, captures: { stream }, captureStatus: { .active }),
                              presentation: .fixture(recorder, reveals: false), clock: clock)
        await store.send(.task) { $0.hasStarted = true }
        await store.receive(\.captureStatusLoaded) { $0.captureStatus = .active }
        await store.receive(\.libraryLoaded) { $0.items = [self.newer, self.older] }
        await store.receive(\.fileURLsResolved) { $0.fileURLs = [self.newer.id: screenshotURL(self.newer.id), self.older.id: screenshotURL(self.older.id)] }
        await store.send(.task)
        #expect(recorder.loads.value == 1)

        continuation.yield(captured)
        await store.receive(\.captureReceived) {
            $0.items = [captured, self.newer, self.older]
            $0.incomingItemID = captured.id
        }
        await store.receive(\.fileURLsResolved) { $0.fileURLs[captured.id] = screenshotURL(captured.id) }
        await store.receive(\.flightLanded) { $0.incomingItemID = nil }
        continuation.finish()
        await store.finish()
    }

    @Test func libraryLoadFailureShowsError() async {
        let recorder = ScreenshotsCallRecorder()
        let failure = ScreenshotFailure(key: ScreenshotFailure.libraryFailedKey)
        let store = makeStore(.init(), client: .fixture(recorder, load: { throw failure }), presentation: .fixture(recorder))
        await store.send(.task) { $0.hasStarted = true }
        await store.receive(\.captureStatusLoaded)
        await store.receive(\.libraryLoaded) { $0.error = failure }
        await store.send(.errorDismissed) { $0.error = nil }
    }

    // MARK: - Flight

    @Test func captureInsertsItemHiddenRevealsSectionAndAwaitsTarget() async {
        let recorder = ScreenshotsCallRecorder(), clock = TestClock()
        let store = makeStore(started([older]), client: .fixture(recorder, known: [older, newer]), presentation: .fixture(recorder), clock: clock)
        await store.send(.captureReceived(newer)) {
            $0.items = [self.newer, self.older]
            $0.incomingItemID = self.newer.id
        }
        await store.receive(\.fileURLsResolved) { $0.fileURLs[self.newer.id] = screenshotURL(self.newer.id) }
        await clock.advance(by: .seconds(1))
        #expect(recorder.reveals.value == 1)
        #expect(store.state.incomingItemID == newer.id)
        #expect(recorder.flights.value.isEmpty)
        await store.send(.flightTargetResolved(itemID: newer.id, screenFrame: frame)) { $0.flyingItemID = self.newer.id }
        await store.receive(\.flightLanded) { $0.incomingItemID = nil; $0.flyingItemID = nil }
    }

    @Test func captureWhenTabHiddenInsertsWithoutFlight() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([older]), client: .fixture(recorder, known: [older, newer]), presentation: .fixture(recorder, reveals: false))
        await store.send(.captureReceived(newer)) {
            $0.items = [self.newer, self.older]
            $0.incomingItemID = self.newer.id
        }
        await store.receive(\.fileURLsResolved) { $0.fileURLs[self.newer.id] = screenshotURL(self.newer.id) }
        await store.receive(\.flightLanded) { $0.incomingItemID = nil }
        #expect(recorder.reveals.value == 1)
        #expect(recorder.flights.value.isEmpty)
    }

    @Test func reduceMotionSkipsFlight() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([]), client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder, reduceMotion: true))
        await store.send(.captureReceived(newer)) { $0.items = [self.newer]; $0.incomingItemID = self.newer.id }
        await store.receive(\.fileURLsResolved) { $0.fileURLs[self.newer.id] = screenshotURL(self.newer.id) }
        await store.receive(\.flightLanded) { $0.incomingItemID = nil }
        #expect(recorder.reveals.value == 0)
        await store.send(.flightTargetResolved(itemID: newer.id, screenFrame: frame))
        #expect(recorder.flights.value.isEmpty)
    }

    @Test func resolvedTargetFliesThenLands() async {
        let recorder = ScreenshotsCallRecorder(), clock = TestClock()
        let store = makeStore(started([newer], incoming: newer.id), client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder), clock: clock)
        await store.send(.flightTargetResolved(itemID: newer.id, screenFrame: frame)) { $0.flyingItemID = self.newer.id }
        await store.receive(\.flightLanded) { $0.incomingItemID = nil; $0.flyingItemID = nil }
        #expect(recorder.flights.value.map(\.0) == [screenshotURL(newer.id)])
        #expect(recorder.flights.value.map(\.1) == [frame])
    }

    @Test func duplicateTargetWhileFlyingDoesNotRestartFlight() async {
        let recorder = ScreenshotsCallRecorder()
        var state = started([newer], incoming: newer.id); state.flyingItemID = newer.id
        let store = makeStore(state, client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder))
        await store.send(.flightTargetResolved(itemID: newer.id, screenFrame: frame))
        #expect(recorder.flights.value.isEmpty)
    }

    @Test func flightTimesOutAfterOneAndAHalfSecondsAndShowsItem() async {
        let recorder = ScreenshotsCallRecorder(), clock = TestClock()
        let store = makeStore(started([]), client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder), clock: clock)
        await store.send(.captureReceived(newer)) { $0.items = [self.newer]; $0.incomingItemID = self.newer.id }
        await store.receive(\.fileURLsResolved) { $0.fileURLs[self.newer.id] = screenshotURL(self.newer.id) }
        await clock.advance(by: .milliseconds(1499))
        for _ in 0..<20 { await Task.megaYield() }
        // Exhaustive store: sending fails if the timer action was already delivered early.
        await store.send(.errorDismissed)
        await clock.advance(by: .milliseconds(1))
        await store.receive(\.flightTimedOut) { $0.incomingItemID = nil }
        // A late target after the timeout no longer flies.
        await store.send(.flightTargetResolved(itemID: newer.id, screenFrame: frame))
        #expect(recorder.flights.value.isEmpty)
    }

    @Test func staleTargetForOtherItemIsIgnored() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([older, newer], incoming: newer.id), client: .fixture(recorder, known: [older, newer]), presentation: .fixture(recorder))
        await store.send(.flightTargetResolved(itemID: older.id, screenFrame: frame))
        await store.send(.flightLanded(older.id))
        await store.send(.flightTimedOut(older.id))
        #expect(store.state.incomingItemID == newer.id)
        #expect(recorder.flights.value.isEmpty)
    }

    @Test func newCaptureDuringFlightLandsPreviousImmediately() async {
        let recorder = ScreenshotsCallRecorder(), clock = TestClock()
        var state = started([older], incoming: older.id); state.flyingItemID = older.id
        let store = makeStore(state, client: .fixture(recorder, known: [older, newer]), presentation: .fixture(recorder), clock: clock)
        await store.send(.captureReceived(newer)) {
            $0.items = [self.newer, self.older]
            $0.incomingItemID = self.newer.id
            $0.flyingItemID = nil
        }
        await store.receive(\.fileURLsResolved) { $0.fileURLs[self.newer.id] = screenshotURL(self.newer.id) }
        await store.send(.flightLanded(older.id))
        await clock.advance(by: .seconds(1.5))
        await store.receive(\.flightTimedOut) { $0.incomingItemID = nil }
    }

    @Test func repeatedCaptureOfKnownItemUpdatesWithoutFlight() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([newer]), client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder))
        await store.send(.captureReceived(newer))
        #expect(recorder.reveals.value == 0)
    }

    // MARK: - Item actions

    @Test func singleTapCopiesAndShowsCopiedFeedbackThenClears() async {
        let recorder = ScreenshotsCallRecorder(), clock = TestClock()
        let store = makeStore(started([newer]), client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder), clock: clock)
        await store.send(.itemTapped(newer.id))
        await store.receive(\.copySucceeded) { $0.copiedItemID = self.newer.id }
        #expect(recorder.copied.value == [screenshotURL(newer.id)])
        await clock.advance(by: .milliseconds(1199))
        for _ in 0..<20 { await Task.megaYield() }
        // Exhaustive store: sending fails if the timer action was already delivered early.
        await store.send(.errorDismissed)
        await clock.advance(by: .milliseconds(1))
        await store.receive(\.copyFeedbackExpired) { $0.copiedItemID = nil }
    }

    @Test func copyFailureSetsError() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([newer]), client: .fixture(recorder, known: [newer], copyResult: false), presentation: .fixture(recorder))
        await store.send(.itemTapped(newer.id))
        await store.receive(\.operationFailed) { $0.error = ScreenshotFailure(key: ScreenshotFailure.copyFailedKey, itemID: self.newer.id) }
    }

    @Test func unknownItemIsNeverResolvedToAPath() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([newer]), client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder))
        let unknown = UUID()
        await store.send(.itemTapped(unknown))
        await store.send(.itemDoubleTapped(unknown))
        await store.send(.editTapped(unknown))
        await store.send(.deleteTapped(unknown))
        await store.send(.pinTapped(unknown))
        await store.finish()
        #expect(recorder.copied.value.isEmpty && recorder.opened.value.isEmpty && recorder.editors.value.isEmpty)
        #expect(recorder.trashed.value.isEmpty && recorder.pins.value.isEmpty)
    }

    @Test func doubleTapOpensDefaultApp() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([newer]), client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder))
        await store.send(.itemDoubleTapped(newer.id))
        await store.finish()
        #expect(recorder.opened.value == [screenshotURL(newer.id)])
    }

    @Test func pinTogglesAndReorders() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([older, newer]), client: .fixture(recorder, known: [older, newer]), presentation: .fixture(recorder))
        var pinnedOlder = older; pinnedOlder.isPinned = true
        await store.send(.pinTapped(older.id))
        await store.receive(\.itemsChanged) { $0.items = [pinnedOlder, self.newer] }
        #expect(recorder.pins.value.map(\.0) == [older.id])
        #expect(recorder.pins.value.map(\.1) == [true])
    }

    @Test func deleteTrashesOnlyThatItem() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([older, newer]), client: .fixture(recorder, known: [older, newer]), presentation: .fixture(recorder))
        await store.send(.deleteTapped(older.id))
        await store.receive(\.trashResponse) {
            $0.items = [self.newer]
            $0.fileURLs = [self.newer.id: screenshotURL(self.newer.id)]
        }
        #expect(recorder.trashed.value == [[older.id]])
    }

    @Test func deleteAllRequiresConfirmationAndSkipsPinned() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([older, newer, pinned]), client: .fixture(recorder, known: [older, newer, pinned]), presentation: .fixture(recorder))
        #expect(store.state.deletableCount == 2)
        await store.send(.deleteAllConfirmed)
        #expect(recorder.trashed.value.isEmpty)
        await store.send(.deleteAllTapped) { $0.isConfirmingDeleteAll = true }
        #expect(recorder.trashed.value.isEmpty)
        await store.send(.deleteAllConfirmed) { $0.isConfirmingDeleteAll = false }
        await store.receive(\.trashResponse) {
            $0.items = [self.pinned]
            $0.fileURLs = [self.pinned.id: screenshotURL(self.pinned.id)]
        }
        #expect(recorder.trashed.value.map(Set.init) == [[older.id, newer.id]])
        #expect(store.state.deletableCount == 0)
        await store.send(.deleteAllTapped)
    }

    @Test func deleteAllCancelledDoesNothing() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([older, newer]), client: .fixture(recorder, known: [older, newer]), presentation: .fixture(recorder))
        await store.send(.deleteAllTapped) { $0.isConfirmingDeleteAll = true }
        await store.send(.deleteAllCancelled) { $0.isConfirmingDeleteAll = false }
        await store.finish()
        #expect(recorder.trashed.value.isEmpty)
        #expect(store.state.items == [newer, older])
    }

    @Test func partialTrashFailureKeepsFailedItemsAndReportsError() async {
        let recorder = ScreenshotsCallRecorder()
        let failure = ScreenshotFailure(key: ScreenshotFailure.trashFailedKey, itemID: older.id)
        let remaining = [older]
        let store = makeStore(started([older, newer]), client: .fixture(recorder, known: [older, newer], trash: { _ in (items: remaining, failures: [failure]) }), presentation: .fixture(recorder))
        await store.send(.deleteAllTapped) { $0.isConfirmingDeleteAll = true }
        await store.send(.deleteAllConfirmed) { $0.isConfirmingDeleteAll = false }
        await store.receive(\.trashResponse) {
            $0.items = [self.older]
            $0.fileURLs = [self.older.id: screenshotURL(self.older.id)]
            $0.error = failure
        }
    }

    @Test func trashingTheIncomingItemCancelsItsFlight() async {
        let recorder = ScreenshotsCallRecorder()
        var state = started([newer], incoming: newer.id); state.copiedItemID = newer.id
        let store = makeStore(state, client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder))
        await store.send(.deleteTapped(newer.id))
        await store.receive(\.trashResponse) { $0.items = []; $0.fileURLs = [:]; $0.incomingItemID = nil; $0.copiedItemID = nil }
    }

    @Test func editTappedOpensEditorForRecordedItem() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([newer]), client: .fixture(recorder, known: [newer]), presentation: .fixture(recorder))
        await store.send(.editTapped(newer.id))
        await store.finish()
        #expect(recorder.editors.value == [newer.id])
    }

    @Test func itemsChangedReordersAndRefreshesFileURLs() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([older]), client: .fixture(recorder, known: [older, newer]), presentation: .fixture(recorder))
        var edited = older; edited.revision = 1
        await store.send(.itemsChanged([edited, newer])) { $0.items = [self.newer, edited] }
        await store.receive(\.fileURLsResolved) { $0.fileURLs[self.newer.id] = screenshotURL(self.newer.id) }
        await store.send(.revealFolderTapped)
        await store.finish()
        #expect(recorder.folderReveals.value == 1)
    }

    // MARK: - Capture takeover

    @Test func captureToggleEnablesThenReloadsStatus() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([], status: .disabled), client: .fixture(recorder, captureStatus: { .active }), presentation: .fixture(recorder))
        await store.send(.captureToggleChanged(true)) { $0.captureStatus = .active }
        await store.receive(\.captureStatusLoaded)
        #expect(recorder.toggles.value == [true])
    }

    @Test func captureToggleDisablesThenReloadsStatus() async {
        let recorder = ScreenshotsCallRecorder()
        let store = makeStore(started([], status: .changedElsewhere), client: .fixture(recorder, captureStatus: { .disabled }), presentation: .fixture(recorder))
        await store.send(.captureToggleChanged(false)) { $0.captureStatus = .disabled }
        await store.receive(\.captureStatusLoaded)
        #expect(recorder.toggles.value == [false])
    }

    @Test func captureToggleFailureRevertsStatusAndShowsError() async {
        let recorder = ScreenshotsCallRecorder()
        let failure = ScreenshotFailure(key: ScreenshotFailure.captureSettingsFailedKey)
        let store = makeStore(started([], status: .disabled), client: .fixture(recorder, captureStatus: { .disabled }, enableCapture: { throw failure }), presentation: .fixture(recorder))
        await store.send(.captureToggleChanged(true)) { $0.captureStatus = .active }
        await store.receive(\.captureFailed) { $0.error = failure }
        await store.receive(\.captureStatusLoaded) { $0.captureStatus = .disabled }
    }
}
#endif
