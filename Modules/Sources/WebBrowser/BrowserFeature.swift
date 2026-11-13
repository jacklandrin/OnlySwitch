import ComposableArchitecture
import Foundation

/// The Browser tab: saved bookmarks, the visible page's toolbar state, and the Settings editor.
/// One store is shared by the menu-bar list, Only Control and Settings.
@Reducer
public struct BrowserFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var bookmarks: IdentifiedArrayOf<BrowserBookmark> = []
        public var selectedID: UUID?
        public var addressText = ""
        public var showsInvalidAddress = false
        public var navigation = BrowserNavigationState()
        public var draft: BrowserBookmarkDraft?
        public var storageCorrupted = false
        public var isClearingWebsiteData = false
        public var hasStarted = false

        public init() {}

        public var selectedBookmark: BrowserBookmark? { selectedID.flatMap { bookmarks[id: $0] } }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case navigationEvent(BrowserNavigationEvent)
        case selectBookmark(UUID)
        case addressTextChanged(String)
        case addressSubmitted
        case goBackTapped
        case goForwardTapped
        case reloadOrStopTapped
        case homeTapped
        case mobileUserAgentToggled(UUID)
        case addCurrentPageTapped
        case openInDefaultBrowserTapped
        case addBookmarkTapped
        case editBookmarkTapped(UUID)
        case draftTitleChanged(String)
        case draftAddressChanged(String)
        case draftMobileUserAgentChanged(Bool)
        case draftSaveTapped
        case draftCancelTapped
        case deleteBookmarkTapped(UUID)
        case moveBookmarks(IndexSet, Int)
        case clearWebsiteDataTapped
        case clearWebsiteDataFinished
    }

    enum CancelID { case events }

    @Dependency(\.browserStorage) var storage
    @Dependency(\.browserWebClient) var webClient
    @Dependency(\.openURL) var openURL
    @Dependency(\.uuid) var uuid

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return start(&state)

            case let .navigationEvent(event):
                guard event.bookmarkID == state.selectedID else { return .none }
                let urlChanged = event.state.currentURL != state.navigation.currentURL
                state.navigation = event.state
                if urlChanged, let url = event.state.currentURL {
                    state.addressText = url.absoluteString
                    state.showsInvalidAddress = false
                }
                return .none

            case let .selectBookmark(id):
                guard id != state.selectedID, state.bookmarks[id: id] != nil else { return .none }
                showPage(id, in: &state)
                return .merge(persist(state), activateSelected(state))

            case let .addressTextChanged(text):
                state.addressText = text
                state.showsInvalidAddress = false
                return .none

            case .addressSubmitted:
                guard let id = state.selectedID else { return .none }
                guard let url = BrowserURLNormalizer.url(from: state.addressText) else {
                    state.showsInvalidAddress = true
                    return .none
                }
                state.addressText = url.absoluteString
                return .run { [webClient] _ in await webClient.load(id, url) }

            case .goBackTapped:
                return command(state) { client, id in await client.goBack(id) }

            case .goForwardTapped:
                return command(state) { client, id in await client.goForward(id) }

            case .reloadOrStopTapped:
                let isLoading = state.navigation.isLoading
                return command(state) { client, id in
                    if isLoading { await client.stop(id) } else { await client.reload(id) }
                }

            case .homeTapped:
                guard let bookmark = state.selectedBookmark else { return .none }
                return .run { [webClient] _ in await webClient.load(bookmark.id, bookmark.url) }

            case .openInDefaultBrowserTapped:
                guard let url = state.navigation.currentURL ?? state.selectedBookmark?.url else { return .none }
                return .run { [openURL] _ in await openURL(url) }

            case .clearWebsiteDataTapped:
                guard !state.isClearingWebsiteData else { return .none }
                state.isClearingWebsiteData = true
                return .run { [webClient] send in
                    await webClient.clearWebsiteData()
                    await send(.clearWebsiteDataFinished)
                }

            case .clearWebsiteDataFinished:
                state.isClearingWebsiteData = false
                return .none

            case .mobileUserAgentToggled, .addCurrentPageTapped, .addBookmarkTapped, .editBookmarkTapped,
                 .draftTitleChanged, .draftAddressChanged, .draftMobileUserAgentChanged, .draftSaveTapped,
                 .draftCancelTapped, .deleteBookmarkTapped, .moveBookmarks:
                return reduceBookmarks(into: &state, action: action)
            }
        }
    }

    /// Loads saved bookmarks once and subscribes to page events for the lifetime of the shared store.
    private func start(_ state: inout State) -> Effect<Action> {
        guard !state.hasStarted else { return .none }
        state.hasStarted = true
        switch storage.load() {
        case let .loaded(stored):
            state.bookmarks = IdentifiedArray(stored.bookmarks, uniquingIDsWith: { first, _ in first })
            let restored = stored.selectedID.flatMap { state.bookmarks[id: $0]?.id }
            showPage(restored ?? state.bookmarks.first?.id, in: &state)
        case .corrupted:
            state.storageCorrupted = true
        }
        return .merge(
            .run { [webClient] send in
                for await event in await webClient.events() {
                    await send(.navigationEvent(event))
                }
            }
            .cancellable(id: CancelID.events, cancelInFlight: true),
            activateSelected(state)
        )
    }

    /// Selects `id` and resets the toolbar to the bookmark's address until the page reports its own state.
    func showPage(_ id: UUID?, in state: inout State) {
        state.selectedID = id
        state.navigation = BrowserNavigationState()
        state.showsInvalidAddress = false
        state.addressText = id.flatMap { state.bookmarks[id: $0]?.url.absoluteString } ?? ""
    }

    func activateSelected(_ state: State) -> Effect<Action> {
        guard let bookmark = state.selectedBookmark else { return .none }
        return .run { [webClient] _ in await webClient.activate(bookmark) }
    }

    private func command(
        _ state: State,
        _ body: @escaping @Sendable (BrowserWebClient, UUID) async -> Void
    ) -> Effect<Action> {
        guard let id = state.selectedID else { return .none }
        return .run { [webClient] _ in await body(webClient, id) }
    }
}
