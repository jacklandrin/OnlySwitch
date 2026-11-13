import ComposableArchitecture
import Extensions
import Foundation
import OSLog

extension BrowserFeature {
    func persist(_ state: State) -> Effect<Action> {
        let stored = BrowserStoredState(bookmarks: Array(state.bookmarks), selectedID: state.selectedID)
        return .run { [storage] _ in
            do {
                try storage.save(stored)
            } catch {
                Logger.browser.error("Saving browser bookmarks failed: \(error.localizedDescription)")
            }
        }
    }

    func reduceBookmarks(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .mobileUserAgentToggled(id):
            guard var bookmark = state.bookmarks[id: id] else { return .none }
            bookmark.usesMobileUserAgent.toggle()
            state.bookmarks[id: id] = bookmark
            let enabled = bookmark.usesMobileUserAgent
            return .merge(persist(state), .run { [webClient] _ in await webClient.setMobileUserAgent(id, enabled) })

        case .addCurrentPageTapped:
            guard let url = state.navigation.currentURL,
                  let scheme = url.scheme?.lowercased(), BrowserURLNormalizer.allowedSchemes.contains(scheme),
                  !state.bookmarks.contains(where: { $0.url == url }) else { return .none }
            state.bookmarks.append(BrowserBookmark(
                id: uuid(),
                title: state.navigation.title,
                url: url,
                usesMobileUserAgent: state.selectedBookmark?.usesMobileUserAgent ?? false
            ))
            return persist(state)

        case .addBookmarkTapped:
            state.draft = BrowserBookmarkDraft()
            return .none

        case let .editBookmarkTapped(id):
            guard let bookmark = state.bookmarks[id: id] else { return .none }
            state.draft = BrowserBookmarkDraft(
                editingID: id,
                title: bookmark.title,
                address: bookmark.url.absoluteString,
                usesMobileUserAgent: bookmark.usesMobileUserAgent
            )
            return .none

        case let .draftTitleChanged(title):
            state.draft?.title = title
            return .none

        case let .draftAddressChanged(address):
            state.draft?.address = address
            state.draft?.showsInvalidAddress = false
            return .none

        case let .draftMobileUserAgentChanged(enabled):
            state.draft?.usesMobileUserAgent = enabled
            return .none

        case .draftCancelTapped:
            state.draft = nil
            return .none

        case .draftSaveTapped:
            return saveDraft(into: &state)

        case let .deleteBookmarkTapped(id):
            guard state.bookmarks.remove(id: id) != nil else { return .none }
            var effects: [Effect<Action>] = [.run { [webClient] _ in await webClient.discard(id) }]
            if state.selectedID == id {
                showPage(state.bookmarks.first?.id, in: &state)
                effects.append(activateSelected(state))
            }
            effects.append(persist(state))
            return .merge(effects)

        case let .moveBookmarks(source, destination):
            state.bookmarks.move(fromOffsets: source, toOffset: destination)
            return persist(state)

        default:
            return .none
        }
    }

    private func saveDraft(into state: inout State) -> Effect<Action> {
        guard var draft = state.draft else { return .none }
        guard let url = BrowserURLNormalizer.url(from: draft.address) else {
            draft.showsInvalidAddress = true
            state.draft = draft
            return .none
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        state.draft = nil

        guard let id = draft.editingID, let previous = state.bookmarks[id: id] else {
            let bookmark = BrowserBookmark(id: uuid(), title: title, url: url, usesMobileUserAgent: draft.usesMobileUserAgent)
            state.bookmarks.append(bookmark)
            guard state.selectedID == nil else { return persist(state) }
            showPage(bookmark.id, in: &state)
            return .merge(persist(state), activateSelected(state))
        }

        state.bookmarks[id: id] = BrowserBookmark(id: id, title: title, url: url, usesMobileUserAgent: draft.usesMobileUserAgent)
        var effects = [persist(state)]
        if previous.usesMobileUserAgent != draft.usesMobileUserAgent {
            let enabled = draft.usesMobileUserAgent
            effects.append(.run { [webClient] _ in await webClient.setMobileUserAgent(id, enabled) })
        }
        // Applied after the user agent change so the new address replaces that reload. Pages that are not
        // alive ignore the load and open the new address when next shown.
        if previous.url != url {
            if state.selectedID == id { state.addressText = url.absoluteString }
            effects.append(.run { [webClient] _ in await webClient.load(id, url) })
        }
        return .concatenate(effects)
    }
}
