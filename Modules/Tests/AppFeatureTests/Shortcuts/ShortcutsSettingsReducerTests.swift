import ComposableArchitecture
import Foundation
import Switches
import Testing
@testable import AppFeature

@MainActor
struct ShortcutsSettingsReducerTests {
    private struct Failure: Error {}

    nonisolated private static let morning = ShortcutOnMarket(
        name: "Morning",
        link: "https://www.icloud.com/shortcuts/morning",
        author: "a",
        description: "d"
    )
    nonisolated private static let downloads = ShortcutOnMarket(
        name: "Downloads",
        link: "https://www.icloud.com/shortcuts/downloads",
        author: "b",
        description: "d"
    )

    nonisolated private static let morningIcon = Data([1])
    nonisolated private static let focusIcon = Data([2])

    private func makeStore(
        state: ShortcutsSettingsReducer.State = .init(),
        installed: LockIsolated<Result<[String], any Error>> = .init(.success(["Morning", "Focus"])),
        saved: [String: Bool]? = ["Morning": true],
        gallery: Result<[ShortcutOnMarket], any Error> = .success([morning, downloads]),
        savedStates: LockIsolated<[[String: Bool]]> = .init([]),
        notifications: LockIsolated<Int> = .init(0),
        cachedIcons: [String: Data] = [:],
        icons: [String: Data]? = nil,
        iconRequests: LockIsolated<[[String]]> = .init([]),
        appearances: LockIsolated<[[ShortcutAppearance]]> = .init([]),
        opened: LockIsolated<[URL]> = .init([]),
        shown: LockIsolated<[String]> = .init([])
    ) -> TestStoreOf<ShortcutsSettingsReducer> {
        let store = TestStore(initialState: state) {
            ShortcutsSettingsReducer()
        } withDependencies: {
            $0.shortcutsSettingsClient = ShortcutsSettingsClient(
                installedShortcutNames: { try installed.value.get() },
                shownStates: { saved },
                saveShownStates: { states in savedStates.withValue { $0.append(states) } },
                notifySettingsChanged: { notifications.withValue { $0 += 1 } },
                cachedIcons: { cachedIcons },
                loadIcons: { names in
                    iconRequests.withValue { $0.append(names) }
                    return icons
                },
                saveAppearances: { values in appearances.withValue { $0.append(values) } },
                fetchGallery: { try gallery.get() },
                openURL: { url in opened.withValue { $0.append(url) } },
                showShortcut: { name in shown.withValue { $0.append(name) } }
            )
        }
        store.exhaustivity = .off
        return store
    }

    private func loadedState(_ shortcuts: [InstalledShortcut]) -> ShortcutsSettingsReducer.State {
        var state = ShortcutsSettingsReducer.State()
        state.hasLoaded = true
        state.shortcuts = IdentifiedArray(uniqueElements: shortcuts)
        return state
    }

    @Test
    func loadMergesSavedVisibilityAndPrunesRemovedShortcuts() async {
        let savedStates = LockIsolated<[[String: Bool]]>([])
        let store = makeStore(
            saved: ["Morning": true, "Deleted": true],
            savedStates: savedStates
        )

        await store.send(.task)
        await store.receive(\.installedLoaded)
        await store.finish()

        #expect(store.state.hasLoaded)
        #expect(store.state.shortcuts.elements == [
            InstalledShortcut(name: "Morning", isShown: true),
            InstalledShortcut(name: "Focus", isShown: false)
        ])
        #expect(savedStates.value == [["Morning": true, "Focus": false]])
    }

    @Test
    func firstLaunchWithoutSavedStateHidesEverything() async {
        let store = makeStore(saved: nil)
        await store.send(.task)
        await store.receive(\.installedLoaded)
        #expect(store.state.shownCount == 0)
    }

    @Test
    func duplicateNamesFromTheCLIDoNotCrash() async {
        let store = makeStore(installed: .init(.success(["Focus", "Focus"])))
        await store.send(.task)
        await store.receive(\.installedLoaded)
        #expect(store.state.shortcuts.ids.elements == ["Focus"])
    }

    @Test
    func failedListLoadKeepsExistingShortcuts() async {
        let installed = LockIsolated<Result<[String], any Error>>(.failure(Failure()))
        let store = makeStore(
            state: loadedState([InstalledShortcut(name: "Morning", isShown: true)]),
            installed: installed
        )
        await store.send(.appBecameActive)
        await store.receive(\.installedLoaded)
        #expect(store.state.shortcuts.ids.elements == ["Morning"])
        #expect(!store.state.isLoadingShortcuts)
    }

    @Test
    func appBecameActiveBeforeFirstLoadDoesNothing() async {
        let store = makeStore()
        await store.send(.appBecameActive)
        #expect(!store.state.isLoadingShortcuts)
    }

    @Test
    func showingAShortcutPersistsAndNotifies() async {
        let savedStates = LockIsolated<[[String: Bool]]>([])
        let notifications = LockIsolated(0)
        let appearances = LockIsolated<[[ShortcutAppearance]]>([])
        var state = loadedState([
            InstalledShortcut(name: "Morning", isShown: true),
            InstalledShortcut(name: "Focus", isShown: false)
        ])
        state.icons = ["Morning": Self.morningIcon, "Focus": Self.focusIcon]
        state.canSyncAppearances = true
        let store = makeStore(
            state: state,
            savedStates: savedStates,
            notifications: notifications,
            appearances: appearances
        )

        await store.send(.setShown(name: "Focus", isShown: true))
        await store.finish()

        #expect(store.state.shortcuts[id: "Focus"]?.isShown == true)
        #expect(savedStates.value == [["Morning": true, "Focus": true]])
        #expect(notifications.value == 1)
        #expect(appearances.value == [[
            ShortcutAppearance(id: "Morning", name: "Morning", iconPNGData: Self.morningIcon),
            ShortcutAppearance(id: "Focus", name: "Focus", iconPNGData: Self.focusIcon)
        ]])
    }

    @Test
    func cannotShowMoreThanTheMaximum() async {
        let full = (0..<ShortcutsSettingsReducer.maximumShown).map { InstalledShortcut(name: "S\($0)", isShown: true) }
        let savedStates = LockIsolated<[[String: Bool]]>([])
        let store = makeStore(
            state: loadedState(full + [InstalledShortcut(name: "Extra", isShown: false)]),
            savedStates: savedStates
        )

        await store.send(.setShown(name: "Extra", isShown: true))

        #expect(store.state.message == .tooManyShown)
        #expect(store.state.shortcuts[id: "Extra"]?.isShown == false)
        #expect(savedStates.value.isEmpty)

        await store.send(.dismissMessage)
        #expect(store.state.message == nil)
    }

    @Test
    func hidingIsAllowedAtTheMaximum() async {
        let full = (0..<ShortcutsSettingsReducer.maximumShown).map { InstalledShortcut(name: "S\($0)", isShown: true) }
        let store = makeStore(state: loadedState(full))
        await store.send(.setShown(name: "S0", isShown: false))
        #expect(store.state.shownCount == ShortcutsSettingsReducer.maximumShown - 1)
        #expect(store.state.message == nil)
    }

    @Test
    func openingTheGalleryLoadsItOnceAndMarksInstalledItems() async {
        let store = makeStore(state: loadedState([InstalledShortcut(name: "Morning", isShown: false)]))

        await store.send(.tabChanged(.gallery))
        #expect(store.state.isLoadingGallery)
        await store.receive(\.galleryLoaded)

        #expect(store.state.gallery.ids.elements == [Self.morning.link, Self.downloads.link])
        #expect(store.state.gallery[id: Self.morning.link]?.isInstalled == true)
        #expect(store.state.gallery[id: Self.downloads.link]?.isInstalled == false)

        await store.send(.tabChanged(.mine))
        await store.send(.tabChanged(.gallery))
        #expect(!store.state.isLoadingGallery)
    }

    @Test
    func galleryFailureShowsRetryOnlyWhenEmpty() async {
        let store = makeStore(gallery: .failure(Failure()))
        await store.send(.tabChanged(.gallery))
        await store.receive(\.galleryLoaded)
        #expect(store.state.galleryLoadFailed)
        #expect(!store.state.isLoadingGallery)
    }

    @Test
    func reloadingInstalledShortcutsUpdatesGalleryStatus() async {
        var state = loadedState([])
        state.gallery = [ShortcutsGalleryItem(Self.downloads)]
        let store = makeStore(state: state, installed: .init(.success(["Downloads"])))

        await store.send(.appBecameActive)
        await store.receive(\.installedLoaded)

        #expect(store.state.gallery[id: Self.downloads.link]?.isInstalled == true)
    }

    @Test
    func addingOpensTheHTTPSLink() async {
        let opened = LockIsolated<[URL]>([])
        var state = loadedState([])
        state.gallery = [ShortcutsGalleryItem(Self.downloads)]
        let store = makeStore(state: state, opened: opened)

        await store.send(.addFromGallery(Self.downloads.link))

        #expect(opened.value == [URL(string: Self.downloads.link)!])
    }

    @Test
    func addingIgnoresNonHTTPSLinks() async {
        let opened = LockIsolated<[URL]>([])
        let unsafe = ShortcutOnMarket(name: "X", link: "file:///Applications/Calculator.app", author: "", description: "")
        var state = loadedState([])
        state.gallery = [ShortcutsGalleryItem(unsafe)]
        let store = makeStore(state: state, opened: opened)

        await store.send(.addFromGallery(unsafe.link))

        #expect(opened.value.isEmpty)
    }

    @Test
    func tappingAnInstalledItemOpensItInShortcuts() async {
        let opened = LockIsolated<[URL]>([])
        let shown = LockIsolated<[String]>([])
        var state = loadedState([InstalledShortcut(name: "Morning", isShown: false)])
        state.gallery = [ShortcutsGalleryItem(Self.morning, isInstalled: true)]
        let store = makeStore(state: state, opened: opened, shown: shown)

        await store.send(.addFromGallery(Self.morning.link))
        await store.receive(\.openInShortcuts)
        await store.finish()

        #expect(opened.value.isEmpty)
        #expect(shown.value == ["Morning"])
    }

    // MARK: - Icons

    @Test
    func cachedIconsShowImmediatelyAndAllIconsAreLoaded() async {
        let requests = LockIsolated<[[String]]>([])
        let appearances = LockIsolated<[[ShortcutAppearance]]>([])
        let store = makeStore(
            cachedIcons: ["Morning": Self.morningIcon, "Deleted": Data([9])],
            icons: ["Morning": Self.morningIcon, "Focus": Self.focusIcon],
            iconRequests: requests,
            appearances: appearances
        )

        await store.send(.task)
        await store.receive(\.installedLoaded)
        #expect(store.state.icons == ["Morning": Self.morningIcon])

        await store.receive(\.iconsLoaded)
        #expect(requests.value == [["Morning", "Focus"]])
        #expect(store.state.icons == ["Morning": Self.morningIcon, "Focus": Self.focusIcon])
        #expect(store.state.canSyncAppearances)
        #expect(appearances.value == [[ShortcutAppearance(id: "Morning", name: "Morning", iconPNGData: Self.morningIcon)]])
    }

    @Test
    func shortcutsClosedKeepsTheCacheAndRetriesLater() async {
        let requests = LockIsolated<[[String]]>([])
        let appearances = LockIsolated<[[ShortcutAppearance]]>([])
        let store = makeStore(
            cachedIcons: ["Morning": Self.morningIcon],
            icons: nil,
            iconRequests: requests,
            appearances: appearances
        )

        await store.send(.task)
        await store.receive(\.installedLoaded)
        await store.receive(\.iconsLoaded)
        #expect(store.state.icons == ["Morning": Self.morningIcon])
        #expect(store.state.fetchedIconNames.isEmpty)
        #expect(appearances.value.isEmpty)

        await store.send(.appBecameActive)
        await store.receive(\.installedLoaded)
        await store.receive(\.iconsLoaded)
        #expect(requests.value.count == 2)
    }

    @Test
    func onlyNewShortcutsAreLookedUpAgainUntilRefresh() async {
        let requests = LockIsolated<[[String]]>([])
        var state = loadedState([InstalledShortcut(name: "Morning", isShown: false)])
        state.fetchedIconNames = ["Morning"]
        state.canSyncAppearances = true
        let store = makeStore(
            state: state,
            icons: [:],
            iconRequests: requests
        )

        await store.send(.appBecameActive)
        await store.receive(\.installedLoaded)
        await store.receive(\.iconsLoaded)
        #expect(requests.value == [["Focus"]])

        await store.send(.refresh)
        await store.receive(\.installedLoaded)
        await store.receive(\.iconsLoaded)
        #expect(requests.value.last == ["Morning", "Focus"])
    }

    @Test
    func showingBeforeIconsAreReadLeavesTheCacheAlone() async {
        let appearances = LockIsolated<[[ShortcutAppearance]]>([])
        let store = makeStore(
            state: loadedState([InstalledShortcut(name: "Focus", isShown: false)]),
            appearances: appearances
        )
        await store.send(.setShown(name: "Focus", isShown: true))
        #expect(appearances.value.isEmpty)
    }

    @Test
    func hidingEverythingClearsTheCache() async {
        let appearances = LockIsolated<[[ShortcutAppearance]]>([])
        let store = makeStore(
            state: loadedState([InstalledShortcut(name: "Focus", isShown: true)]),
            appearances: appearances
        )
        await store.send(.setShown(name: "Focus", isShown: false))
        #expect(appearances.value == [[]])
    }
}
