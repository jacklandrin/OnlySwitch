//
//  ShortcutsSettingsReducer.swift
//  OnlySwitch
//

import ComposableArchitecture
import Foundation
import Switches

/// Settings › Shortcuts: which installed Shortcuts appear in the menu, and the community gallery.
@Reducer
struct ShortcutsSettingsReducer {
    /// The menu shows at most this many Shortcuts.
    static let maximumShown = 10

    enum Tab: Equatable, Sendable {
        case mine
        case gallery
    }

    enum CancelID { case icons }

    enum Message: Equatable, Sendable {
        case tooManyShown
    }

    @ObservableState
    struct State: Equatable {
        var tab: Tab = .mine
        var shortcuts: IdentifiedArrayOf<InstalledShortcut> = []
        var hasLoaded = false
        var isLoadingShortcuts = false
        var gallery: IdentifiedArrayOf<ShortcutsGalleryItem> = []
        var isLoadingGallery = false
        var galleryLoadFailed = false
        var message: Message?
        /// PNG icons keyed by Shortcut name: the shared cache first, then the Shortcuts app.
        var icons: [String: Data] = [:]
        /// Names already looked up in the Shortcuts app this session.
        var fetchedIconNames: Set<String> = []
        /// True once icons were read from the Shortcuts app, so the shared cache can be rewritten from `icons`.
        var canSyncAppearances = false

        var shownCount: Int { shortcuts.filter(\.isShown).count }
        var installedNames: Set<String> { Set(shortcuts.ids) }
    }

    enum Action {
        case task
        case refresh
        case appBecameActive
        case tabChanged(Tab)
        case installedLoaded(Result<[String], any Error>)
        case iconsLoaded(requested: [String], icons: [String: Data]?)
        case setShown(name: String, isShown: Bool)
        case openInShortcuts(name: String)
        case galleryLoaded(Result<[ShortcutOnMarket], any Error>)
        case addFromGallery(ShortcutsGalleryItem.ID)
        case dismissMessage
    }

    @Dependency(\.shortcutsSettingsClient) var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                guard !state.hasLoaded else { return .none }
                return loadInstalled(&state)

            case .refresh:
                state.fetchedIconNames = []
                return .merge(loadInstalled(&state), loadGallery(&state))

            case .appBecameActive:
                // Returning from the Shortcuts app may have added or removed Shortcuts.
                guard state.hasLoaded else { return .none }
                return loadInstalled(&state)

            case let .tabChanged(tab):
                state.tab = tab
                guard tab == .gallery, state.gallery.isEmpty, !state.isLoadingGallery else { return .none }
                return loadGallery(&state)

            case let .installedLoaded(.success(names)):
                state.isLoadingShortcuts = false
                state.hasLoaded = true
                let saved = client.shownStates() ?? [:]
                let shortcuts = names.map { InstalledShortcut(name: $0, isShown: saved[$0] ?? false) }
                state.shortcuts = IdentifiedArray(shortcuts, uniquingIDsWith: { first, _ in first })
                markInstalledGalleryItems(&state)
                client.saveShownStates(shownStates(state))
                let installed = state.installedNames
                state.icons = state.icons
                    .filter { installed.contains($0.key) }
                    .merging(client.cachedIcons().filter { installed.contains($0.key) }) { current, _ in current }
                syncAppearances(state)
                return loadIcons(&state)

            case let .iconsLoaded(requested, icons):
                // `nil`: Shortcuts isn't running; keep the cached icons and try again later.
                guard let icons else { return .none }
                state.fetchedIconNames.formUnion(requested)
                state.icons.merge(icons) { _, new in new }
                state.canSyncAppearances = true
                syncAppearances(state)
                return .none

            case .installedLoaded(.failure):
                state.isLoadingShortcuts = false
                state.hasLoaded = true
                return .none

            case let .setShown(name, isShown):
                guard let current = state.shortcuts[id: name], current.isShown != isShown else { return .none }
                if isShown, state.shownCount >= Self.maximumShown {
                    state.message = .tooManyShown
                    return .none
                }
                state.shortcuts[id: name]?.isShown = isShown
                client.saveShownStates(shownStates(state))
                client.notifySettingsChanged()
                syncAppearances(state)
                return .none

            case let .openInShortcuts(name):
                return .run { _ in await client.showShortcut(name) }

            case let .galleryLoaded(.success(list)):
                state.isLoadingGallery = false
                state.galleryLoadFailed = false
                let installed = state.installedNames
                let items = list.map { ShortcutsGalleryItem($0, isInstalled: installed.contains($0.name)) }
                state.gallery = IdentifiedArray(items, uniquingIDsWith: { first, _ in first })
                return .none

            case .galleryLoaded(.failure):
                state.isLoadingGallery = false
                state.galleryLoadFailed = state.gallery.isEmpty
                return .none

            case let .addFromGallery(id):
                guard let item = state.gallery[id: id] else { return .none }
                if item.isInstalled {
                    return .send(.openInShortcuts(name: item.name))
                }
                guard let url = item.linkURL else { return .none }
                client.openURL(url)
                return .none

            case .dismissMessage:
                state.message = nil
                return .none
            }
        }
    }

    private func loadInstalled(_ state: inout State) -> Effect<Action> {
        state.isLoadingShortcuts = true
        return .run { send in
            do {
                await send(.installedLoaded(.success(try await client.installedShortcutNames())))
            } catch {
                await send(.installedLoaded(.failure(error)))
            }
        }
    }

    private func loadIcons(_ state: inout State) -> Effect<Action> {
        let fetched = state.fetchedIconNames
        let missing = state.shortcuts.map(\.name).filter { !fetched.contains($0) }
        guard !missing.isEmpty else { return .none }
        return .run { send in
            await send(.iconsLoaded(requested: missing, icons: await client.loadIcons(missing)))
        }
        .cancellable(id: CancelID.icons, cancelInFlight: true)
    }

    /// Rewrites the menu's appearance cache for the shown Shortcuts. Before icons were read
    /// from the Shortcuts app the cache is left alone, unless nothing is shown.
    private func syncAppearances(_ state: State) {
        let shown = state.shortcuts.filter(\.isShown).map(\.name)
        guard shown.isEmpty || state.canSyncAppearances else { return }
        client.saveAppearances(shown.compactMap { name in
            state.icons[name].map { ShortcutAppearance(id: name, name: name, iconPNGData: $0) }
        })
    }

    private func loadGallery(_ state: inout State) -> Effect<Action> {
        state.isLoadingGallery = true
        state.galleryLoadFailed = false
        return .run { send in
            do {
                await send(.galleryLoaded(.success(try await client.fetchGallery())))
            } catch {
                await send(.galleryLoaded(.failure(error)))
            }
        }
    }

    private func markInstalledGalleryItems(_ state: inout State) {
        let installed = state.installedNames
        state.gallery = IdentifiedArray(uniqueElements: state.gallery.map { item in
            var item = item
            item.isInstalled = installed.contains(item.name)
            return item
        })
    }

    private func shownStates(_ state: State) -> [String: Bool] {
        Dictionary(state.shortcuts.map { ($0.name, $0.isShown) }, uniquingKeysWith: { first, _ in first })
    }
}
