#if os(macOS)
import ComposableArchitecture
import CoreGraphics
import Foundation

/// The Screenshots tab: library, capture takeover toggle, copy/open/pin/delete/delete-all and fly-in
/// orchestration. One session store lives in `SettingsVM`, so the capture subscription is app-lifetime.
@Reducer
public struct ScreenshotsFeature {
    @ObservableState
    public struct State: Equatable {
        /// Always `displayOrdered()`.
        public var items: [ScreenshotItem] = []
        /// Resolved by the reducer through `client.fileURL` whenever items change, so views can drag synchronously.
        public var fileURLs: [UUID: URL] = [:]
        /// The newest capture's cell stays hidden until its flight lands, times out or is skipped.
        public var incomingItemID: UUID?
        /// Set while the overlay animation for `incomingItemID` is running; a repeated target is ignored.
        public var flyingItemID: UUID?
        public var copiedItemID: UUID?
        public var isConfirmingDeleteAll = false
        public var captureStatus: ScreenshotCaptureStatus = .disabled
        public var error: ScreenshotFailure?
        public var hasStarted = false
        /// True while the external-capture (Device Hub) effect has been started for the current enabled period.
        public var isCollectingExternalCaptures = false
        public init() {}
        public var deletableCount: Int { items.filter { !$0.isPinned }.count }
    }

    public enum Action: Equatable, Sendable {
        case task
        case libraryLoaded(Result<[ScreenshotItem], ScreenshotFailure>)
        case fileURLsResolved([UUID: URL])
        case captureReceived(ScreenshotItem)
        case flightTargetResolved(itemID: UUID, screenFrame: CGRect)
        case flightTimedOut(UUID)
        case flightLanded(UUID)
        case itemTapped(UUID)
        case itemDoubleTapped(UUID)
        case pinTapped(UUID)
        case deleteTapped(UUID)
        case editTapped(UUID)
        case deleteAllTapped
        case deleteAllConfirmed
        case deleteAllCancelled
        case itemsChanged([ScreenshotItem])
        case trashResponse(items: [ScreenshotItem], failures: [ScreenshotFailure])
        case copySucceeded(UUID)
        case copyFeedbackExpired(UUID)
        case operationFailed(ScreenshotFailure)
        case captureToggleChanged(Bool)
        case captureStatusLoaded(ScreenshotCaptureStatus)
        case captureFailed(ScreenshotFailure)
        case revealFolderTapped
        case errorDismissed
    }

    @Dependency(\.screenshotsClient) var client
    @Dependency(\.screenshotPresentationClient) var presentation
    @Dependency(\.continuousClock) var clock
    private enum CancelID { case captures, externalCaptures, flightTimeout, flight, copyFeedback }
    static let flightTimeout: Duration = .seconds(1.5)
    static let copyFeedbackDuration: Duration = .seconds(1.2)

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                guard !state.hasStarted else { return .none }
                state.hasStarted = true
                return .merge(
                    .run { [client] send in
                        await send(.captureStatusLoaded(await client.captureStatus()))
                        do { await send(.libraryLoaded(.success(try await client.load()))) }
                        catch { await send(.libraryLoaded(.failure(Self.failure(error, key: ScreenshotFailure.libraryFailedKey)))) }
                    },
                    .run { [client] send in
                        for await item in client.captures() { await send(.captureReceived(item)) }
                    }.cancellable(id: CancelID.captures)
                )

            case let .libraryLoaded(.success(items)):
                // Keep captures that arrived while the initial load was in flight.
                let loaded = Set(items.map(\.id))
                return setItems(items + state.items.filter { !loaded.contains($0.id) }, &state)
            case let .libraryLoaded(.failure(failure)):
                state.error = failure
                return .none

            case let .fileURLsResolved(urls):
                let ids = Set(state.items.map(\.id))
                for (id, url) in urls where ids.contains(id) { state.fileURLs[id] = url }
                return .none

            case let .captureReceived(item):
                if state.items.contains(where: { $0.id == item.id }) {
                    // Already listed (e.g. adopted by the initial load): update it, no flight.
                    return setItems(state.items.map { $0.id == item.id ? item : $0 }, &state)
                }
                // A previous capture still waiting or flying lands immediately without animation.
                state.flyingItemID = nil
                state.incomingItemID = item.id
                let sync = setItems(state.items + [item], &state)
                let id = item.id
                let flight: Effect<Action> = .run { [presentation, clock] send in
                    guard await !presentation.reduceMotion(), await presentation.revealScreenshotsSection() else {
                        await send(.flightLanded(id)); return
                    }
                    try await clock.sleep(for: Self.flightTimeout)
                    await send(.flightTimedOut(id))
                }.cancellable(id: CancelID.flightTimeout, cancelInFlight: true)
                return .merge(.cancel(id: CancelID.flight), .concatenate(sync, flight))

            case let .flightTargetResolved(id, frame):
                guard state.incomingItemID == id, state.flyingItemID != id else { return .none }
                state.flyingItemID = id
                return .merge(
                    .cancel(id: CancelID.flightTimeout),
                    .run { [client, presentation] send in
                        if let url = await client.fileURL(id) { await presentation.flyIn(url, frame) }
                        await send(.flightLanded(id))
                    }.cancellable(id: CancelID.flight, cancelInFlight: true)
                )

            case let .flightLanded(id):
                guard state.incomingItemID == id else { return .none }
                state.incomingItemID = nil; state.flyingItemID = nil
                return .none
            case let .flightTimedOut(id):
                guard state.incomingItemID == id, state.flyingItemID != id else { return .none }
                state.incomingItemID = nil
                return .none

            case let .itemTapped(id):
                guard contains(id, state) else { return .none }
                return .run { [client] send in
                    guard let url = await client.fileURL(id) else { return }
                    if await client.copyToPasteboard(url) { await send(.copySucceeded(id)) }
                    else { await send(.operationFailed(.init(key: ScreenshotFailure.copyFailedKey, itemID: id))) }
                }
            case let .copySucceeded(id):
                state.copiedItemID = id
                return .run { [clock] send in
                    try await clock.sleep(for: Self.copyFeedbackDuration)
                    await send(.copyFeedbackExpired(id))
                }.cancellable(id: CancelID.copyFeedback, cancelInFlight: true)
            case let .copyFeedbackExpired(id):
                if state.copiedItemID == id { state.copiedItemID = nil }
                return .none

            case let .itemDoubleTapped(id):
                guard contains(id, state) else { return .none }
                return .run { [client] _ in
                    if let url = await client.fileURL(id) { await client.openInDefaultApp(url) }
                }

            case let .pinTapped(id):
                guard let item = state.items.first(where: { $0.id == id }) else { return .none }
                return .run { [client] send in
                    do { await send(.itemsChanged(try await client.setPinned(id, !item.isPinned))) }
                    catch { await send(.operationFailed(Self.failure(error, key: ScreenshotFailure.libraryFailedKey, itemID: id))) }
                }

            case let .deleteTapped(id):
                guard contains(id, state) else { return .none }
                return trash([id])
            case .deleteAllTapped:
                guard state.deletableCount > 0 else { return .none }
                state.isConfirmingDeleteAll = true
                return .none
            case .deleteAllConfirmed:
                guard state.isConfirmingDeleteAll else { return .none }
                state.isConfirmingDeleteAll = false
                let ids = state.items.filter { !$0.isPinned }.map(\.id)
                return ids.isEmpty ? .none : trash(ids)
            case .deleteAllCancelled:
                state.isConfirmingDeleteAll = false
                return .none
            case let .trashResponse(items, failures):
                if let failure = failures.first { state.error = failure }
                return setItems(items, &state)

            case let .editTapped(id):
                guard contains(id, state) else { return .none }
                return .run { [presentation] _ in await presentation.openEditor(id) }

            case let .itemsChanged(items):
                return setItems(items, &state)

            case let .operationFailed(failure):
                state.error = failure
                return .none

            case let .captureToggleChanged(isOn):
                state.captureStatus = isOn ? .active : .disabled
                return .run { [client] send in
                    do {
                        if isOn { try await client.enableCapture() } else { try await client.disableCapture() }
                        await send(.captureStatusLoaded(await client.captureStatus()))
                    } catch {
                        await send(.captureFailed(Self.failure(error, key: ScreenshotFailure.captureSettingsFailedKey)))
                    }
                }
            case let .captureStatusLoaded(status):
                state.captureStatus = status
                if status == .disabled {
                    guard state.isCollectingExternalCaptures else { return .none }
                    state.isCollectingExternalCaptures = false
                    return .cancel(id: CancelID.externalCaptures)
                }
                guard !state.isCollectingExternalCaptures else { return .none }
                state.isCollectingExternalCaptures = true
                return .run { [client] _ in await client.collectExternalCaptures() }.cancellable(id: CancelID.externalCaptures)
            case let .captureFailed(failure):
                state.error = failure
                // Revert the optimistic toggle to whatever the system actually has now.
                return .run { [client] send in await send(.captureStatusLoaded(await client.captureStatus())) }

            case .revealFolderTapped:
                return .run { [client] _ in await client.revealFolder() }
            case .errorDismissed:
                state.error = nil
                return .none
            }
        }
    }

    // MARK: - Helpers

    private func contains(_ id: UUID, _ state: State) -> Bool { state.items.contains { $0.id == id } }

    private func trash(_ ids: [UUID]) -> Effect<Action> {
        .run { [client] send in
            let result = await client.trash(ids)
            await send(.trashResponse(items: result.items, failures: result.failures))
        }
    }

    /// Replaces the list (ordered), drops per-item UI state for removed ids and resolves missing file URLs.
    private func setItems(_ items: [ScreenshotItem], _ state: inout State) -> Effect<Action> {
        state.items = items.displayOrdered()
        let ids = Set(state.items.map(\.id))
        state.fileURLs = state.fileURLs.filter { ids.contains($0.key) }
        var effects: [Effect<Action>] = []
        if let incoming = state.incomingItemID, !ids.contains(incoming) {
            state.incomingItemID = nil; state.flyingItemID = nil
            effects += [.cancel(id: CancelID.flightTimeout), .cancel(id: CancelID.flight)]
        }
        if let copied = state.copiedItemID, !ids.contains(copied) { state.copiedItemID = nil }
        let missing = state.items.map(\.id).filter { state.fileURLs[$0] == nil }
        if !missing.isEmpty {
            effects.append(.run { [client] send in
                var urls: [UUID: URL] = [:]
                for id in missing { if let url = await client.fileURL(id) { urls[id] = url } }
                if !urls.isEmpty { await send(.fileURLsResolved(urls)) }
            })
        }
        return .merge(effects)
    }

    private static func failure(_ error: any Error, key: String, itemID: UUID? = nil) -> ScreenshotFailure {
        (error as? ScreenshotFailure) ?? ScreenshotFailure(key: key, itemID: itemID)
    }
}
#endif
