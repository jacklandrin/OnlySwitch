import AppKit
import ComposableArchitecture
import Defines
import Extensions
import Foundation
import KeyboardShortcuts
import Screenshots
import Testing
@testable import OnlySwitch

@MainActor
struct ScreenshotsSectionTests {
    @Test func screenshotShortcutHasIndependentPersistentIdentity() {
        #expect(KeyboardShortcuts.Name.openScreenshotsTab.rawValue == "openScreenshotsTab")
        #expect(KeyboardShortcuts.Name.openScreenshotsTab != .invokePopoverShortcutsName)
    }

    @Test func screenshotsAndUninstallerRetainOutsideClicks() {
        for section in SectionBar.sections(authenticator: true, soundMixer: true, systemMonitor: true, codexUsage: true,
                                           claudeUsage: true, aphrodite: true, xcodeCleaner: true, appUninstaller: true, screenshots: true) {
            #expect(section.allowsOutsideClickDismissal == ![.appUninstaller, .screenshots].contains(section))
        }
    }

    @Test func screenshotsSectionIsLastAndHiddenWhenDisabled() {
        #expect(SectionBar.sections(authenticator: false, soundMixer: false, systemMonitor: false, codexUsage: false, screenshots: true).last == .screenshots)
        #expect(!SectionBar.sections(authenticator: false, soundMixer: false, systemMonitor: false, codexUsage: false).contains(.screenshots))
        let all = SectionBar.sections(authenticator: true, soundMixer: true, systemMonitor: true, codexUsage: true,
                                      claudeUsage: true, aphrodite: true, xcodeCleaner: true, appUninstaller: true, screenshots: true)
        #expect(all == [.controls, .authenticator, .soundMixer, .systemMonitor, .codexUsage, .claudeUsage, .aphrodite, .xcodeCleaner, .appUninstaller, .screenshots])
        #expect(SectionBar.Section.screenshots.symbolName == "photo.on.rectangle.angled")
        #expect(SectionBar.Section.screenshots.assetName == nil)
        #expect(!SectionBar.Section.screenshots.title.isEmpty)
    }

    @Test func onlyControlRevealSelectsScreenshots() async {
        let store = TestStore(initialState: OnlyControlReducer.State(selectedSection: .controls)) { OnlyControlReducer() }
        await store.send(.selectedSectionChanged(.screenshots)) { $0.selectedSection = .screenshots }
        await store.receive(\.systemMonitor.visibilityChanged)
        #expect(!store.state.selectedSection.allowsOutsideClickDismissal)
    }

    @Test func hidingSelectedScreenshotsReturnsOnlyControlToControls() async {
        let store = TestStore(initialState: OnlyControlReducer.State(selectedSection: .screenshots)) { OnlyControlReducer() }
        await store.send(.availableSectionsChanged([.controls])) { $0.selectedSection = .controls }
        #expect(store.state.selectedSection.allowsOutsideClickDismissal)
    }

    @Test func visibilityKeyIsExportableButCaptureTakeoverStateIsNot() {
        #expect(UserDefaults.Key.showScreenshotsTab == "showScreenshotsTabKey")
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.showScreenshotsTab))
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.screenshotsCaptureEnabled))
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.screenshotsPreviousCaptureSettings))
    }

    @Test func revealIsRefusedWhileTheTabIsHidden() throws {
        let suite = "ScreenshotsSectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let posts = TestMutex(0)
        let observer = center.addObserver(forName: .revealScreenshotsSection, object: nil, queue: nil) { _ in posts.withLock { $0 += 1 } }
        defer { center.removeObserver(observer) }
        let revealStore = Store(initialState: ScreenshotSectionRevealFeature.State()) { ScreenshotSectionRevealFeature() }
        let client = ScreenshotPresentationClient.app(defaults: defaults, notificationCenter: center, revealStore: revealStore, appearance: { .single })

        defaults.set(false, forKey: UserDefaults.Key.showScreenshotsTab)
        #expect(client.revealScreenshotsSection() == false)
        #expect(posts.withLock { $0 } == 0)
        #expect(revealStore.pendingHost == nil)
    }

    @Test func revealPostsOnceWhenTheTabIsVisibleOrUnset() throws {
        let suite = "ScreenshotsSectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let posts = TestMutex(0)
        let observer = center.addObserver(forName: .revealScreenshotsSection, object: nil, queue: nil) { _ in posts.withLock { $0 += 1 } }
        defer { center.removeObserver(observer) }
        let revealStore = Store(initialState: ScreenshotSectionRevealFeature.State()) { ScreenshotSectionRevealFeature() }
        let client = ScreenshotPresentationClient.app(defaults: defaults, notificationCenter: center, revealStore: revealStore, appearance: { .single })

        #expect(client.revealScreenshotsSection())
        #expect(posts.withLock { $0 } == 1)
        defaults.set(true, forKey: UserDefaults.Key.showScreenshotsTab)
        #expect(client.revealScreenshotsSection())
        #expect(posts.withLock { $0 } == 2)
    }

    @Test func screenshotShortcutRevealDoesNotRequireCaptureCollection() throws {
        let suite = "ScreenshotsSectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: UserDefaults.Key.showScreenshotsTab)
        defaults.set(false, forKey: UserDefaults.Key.screenshotsCaptureEnabled)
        let center = NotificationCenter()
        let posts = TestMutex(0)
        let observer = center.addObserver(forName: .revealScreenshotsSection, object: nil, queue: nil) { _ in posts.withLock { $0 += 1 } }
        defer { center.removeObserver(observer) }
        let revealStore = Store(initialState: ScreenshotSectionRevealFeature.State()) { ScreenshotSectionRevealFeature() }
        let client = ScreenshotPresentationClient.app(defaults: defaults, notificationCenter: center, revealStore: revealStore, appearance: { .single })

        #expect(client.revealScreenshotsSection())
        #expect(revealStore.pendingHost == .popover)
        #expect(posts.withLock { $0 } == 1)
        #expect(defaults.bool(forKey: UserDefaults.Key.screenshotsCaptureEnabled) == false)
    }

    @Test func screenshotShortcutDecisionUsesExactSectionAndVisibility() {
        for section in [SectionBar.Section.controls, .appUninstaller, .screenshots] {
            for shown in [false, true] {
                #expect(ScreenshotShortcutAction.resolve(tabVisible: false, hostShown: shown, selectedSection: section) == .none)
                let expected: ScreenshotShortcutAction = shown && section == .screenshots ? .hide : .reveal
                #expect(ScreenshotShortcutAction.resolve(tabVisible: true, hostShown: shown, selectedSection: section) == expected)
            }
        }
    }

    @Test func screenshotShortcutClosesOnlyShownScreenshotsAndOtherwiseReveals() throws {
        let suite = "ScreenshotsSectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: UserDefaults.Key.showScreenshotsTab)
        for section in [SectionBar.Section.controls, .appUninstaller, .screenshots] {
            for shown in [false, true] {
                let popover = ScreenshotsPopoverSpy(isShown: shown)
                let controller = StatusBarController(popover, appearance: { .single }, configuresSystemIntegrations: false)
                controller.listSelectedSection = section
                let reveals = TestMutex(0)
                var presentation = ScreenshotPresentationClient.testValue
                presentation.revealScreenshotsSection = { reveals.withLock { $0 += 1 }; return true }
                controller.toggleScreenshotsSection(defaults: defaults, presentation: presentation)
                let closes = shown && section == .screenshots
                #expect(popover.closeCount == (closes ? 1 : 0))
                #expect(reveals.withLock { $0 } == (closes ? 0 : 1))
            }
        }
    }

    @Test func hiddenScreenshotsShortcutNeitherClosesNorReveals() throws {
        let suite = "ScreenshotsSectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: UserDefaults.Key.showScreenshotsTab)
        let popover = ScreenshotsPopoverSpy(isShown: true)
        let controller = StatusBarController(popover, appearance: { .single }, configuresSystemIntegrations: false)
        controller.listSelectedSection = .screenshots
        let reveals = TestMutex(0)
        var presentation = ScreenshotPresentationClient.testValue
        presentation.revealScreenshotsSection = { reveals.withLock { $0 += 1 }; return true }
        controller.toggleScreenshotsSection(defaults: defaults, presentation: presentation)
        #expect(popover.closeCount == 0)
        #expect(reveals.withLock { $0 } == 0)
    }

    @Test func screenshotRevealBeforeMountRemainsPendingUntilMatchingHostConsumes() async {
        let store = TestStore(initialState: ScreenshotSectionRevealFeature.State()) { ScreenshotSectionRevealFeature() }
        await store.send(.request(.popover)) { $0.pendingHost = .popover }
        // No host exists yet. An inactive host cannot steal the request when it mounts first.
        await store.send(.consumed(.onlyControl))
        #expect(store.state.pendingHost == .popover)
        await store.send(.consumed(.popover)) { $0.pendingHost = nil }
        // An ordinary reopening has no new selection intent to replay.
        await store.send(.consumed(.popover))
    }

    @Test func subsequentCaptureCreatesNewRevealAfterPreviousSelectionWasConsumed() async {
        let store = TestStore(initialState: ScreenshotSectionRevealFeature.State()) { ScreenshotSectionRevealFeature() }
        await store.send(.request(.onlyControl)) { $0.pendingHost = .onlyControl }
        await store.send(.consumed(.onlyControl)) { $0.pendingHost = nil }
        await store.send(.request(.onlyControl)) { $0.pendingHost = .onlyControl }
        await store.send(.consumed(.onlyControl)) { $0.pendingHost = nil }
    }

    @Test(arguments: [SwitchListAppearance.single, .dual, .onlyControl])
    func screenshotRevealRecordsCorrectHostBeforePostingNotification(appearance: SwitchListAppearance) throws {
        let suite = "ScreenshotsSectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let revealStore = Store(initialState: ScreenshotSectionRevealFeature.State()) { ScreenshotSectionRevealFeature() }
        let expected: ScreenshotSectionRevealFeature.Host = appearance == .onlyControl ? .onlyControl : .popover
        let pendingAtNotification = TestMutex<ScreenshotSectionRevealFeature.Host?>(nil)
        let observer = center.addObserver(forName: .revealScreenshotsSection, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated {
                pendingAtNotification.withLock { $0 = revealStore.pendingHost }
            }
        }
        defer { center.removeObserver(observer) }
        let client = ScreenshotPresentationClient.app(defaults: defaults, notificationCenter: center, revealStore: revealStore, appearance: { appearance })

        #expect(client.revealScreenshotsSection())
        #expect(pendingAtNotification.withLock { $0 } == expected)
        #expect(revealStore.pendingHost == expected)
    }

    @Test func revealShowsHiddenPopoverAndLeavesShownPopoverAlone() {
        let hidden = ScreenshotsPopoverSpy(isShown: false)
        let controller = StatusBarController(hidden, appearance: { .single }, configuresSystemIntegrations: false)
        controller.revealScreenshotsHost()
        #expect(hidden.showCount == 1)
        #expect(hidden.isShown)
        controller.revealScreenshotsHost()
        #expect(hidden.showCount == 1)

        let shown = ScreenshotsPopoverSpy(isShown: true)
        let shownController = StatusBarController(shown, appearance: { .single }, configuresSystemIntegrations: false)
        shownController.revealScreenshotsHost()
        #expect(shown.showCount == 0)
        #expect(shown.closeCount == 0)
    }

    @Test func screenshotsOutsideClickKeepsShownPopoverOpenButExplicitHideCloses() {
        let popover = ScreenshotsPopoverSpy(isShown: true)
        let controller = StatusBarController(popover, appearance: { .single }, configuresSystemIntegrations: false)
        controller.listPreventsOutsideClickDismissal = !SectionBar.Section.screenshots.allowsOutsideClickDismissal

        controller.mouseEventHandler(nil)
        #expect(popover.closeCount == 0)

        controller.hidePopover(nil)
        #expect(popover.closeCount == 1)
    }

    @Test func screenshotsSettingsPageFollowsAppUninstaller() {
        let items = SettingsItem.allCases
        #expect(SettingsItem.Screenshots.rawValue == "Screenshots")
        #expect(items.firstIndex(of: .Screenshots) == items.firstIndex(of: .AppUninstaller).map { $0 + 1 })
    }
}

@MainActor
private final class ScreenshotsPopoverSpy: NSPopover {
    private var simulatedIsShown: Bool
    private(set) var showCount = 0
    private(set) var closeCount = 0

    init(isShown: Bool) {
        simulatedIsShown = isShown
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isShown: Bool { simulatedIsShown }

    override func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        showCount += 1
        simulatedIsShown = true
    }

    override func performClose(_ sender: Any?) {
        closeCount += 1
        simulatedIsShown = false
    }
}
