import AppKit
import ComposableArchitecture
import Defines
import Extensions
import Foundation
import RemoteCore
import Switches
import Testing
@testable import OnlySwitch

@MainActor
struct AppUninstallerSwitchTests {
    @Test func visibilityProviderReadsAndWritesBothStatesWithoutTouchingOtherSwitches() async throws {
        var shown = false
        let provider = AppUninstallerSwitch(visibility: { shown }, setVisibility: { shown = $0 }, notifySettingsChanged: {})
        #expect(provider.type == .appUninstaller)
        #expect(await provider.currentInfo() == "")
        #expect(await provider.currentStatus() == false)
        try await provider.operateSwitch(isOn: true)
        #expect(shown)
        #expect(await provider.currentStatus())
        try await provider.operateSwitch(isOn: false)
        #expect(!shown)
        #expect(provider.isVisible())
    }

    @Test func changingVisibilityPostsSettingsRefresh() async throws {
        let notifications = TestMutex(0)
        let center = NotificationCenter()
        let observer = center.addObserver(forName: .changeSettings, object: nil, queue: nil) { _ in notifications.withLock { $0 += 1 } }
        defer { center.removeObserver(observer) }
        let provider = AppUninstallerSwitch(visibility: { false }, setVisibility: { _ in }, notifySettingsChanged: {
            center.post(name: .changeSettings, object: nil)
        })
        try await provider.operateSwitch(isOn: true)
        #expect(notifications.withLock { $0 } >= 1)
    }

    @Test func missingPreferenceDefaultsToVisibleAndSettingUsesOneSharedKey() async throws {
        let suite = "AppUninstallerVisibilityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = AppUninstallerSwitch(
            visibility: { defaults.object(forKey: UserDefaults.Key.showAppUninstallerTab) as? Bool ?? true },
            setVisibility: { defaults.set($0, forKey: UserDefaults.Key.showAppUninstallerTab) },
            notifySettingsChanged: {}
        )
        #expect(await provider.currentStatus())
        try await provider.operateSwitch(isOn: false)
        #expect(defaults.object(forKey: "showAppUninstallerTabKey") as? Bool == false)
        defaults.set(true, forKey: UserDefaults.Key.showAppUninstallerTab)
        #expect(await provider.currentStatus())
    }

    @Test func stableIdentityMetadataAndBackupEligibilityRemainExplicit() {
        #expect(SwitchType.appUninstaller.legacyIdentifier == 140_737_488_355_328)
        #expect(SwitchType(legacyIdentifier: 140_737_488_355_328) == .appUninstaller)
        #expect(SwitchType.allCases.last == .appUninstaller)
        #expect(Set(SwitchType.allCases.map(\.legacyIdentifier)).count == SwitchType.allCases.count)
        #expect(SwitchType.xcodeCleaner.legacyIdentifier == 70_368_744_177_664)
        #expect(SwitchType.claudeUsage.legacyIdentifier == 35_184_372_088_832)
        #expect(SwitchType.xcodeCache.legacyIdentifier == 2_048)
        #expect(SwitchType.appUninstaller.barInfo().title == "App Uninstaller")
        #expect(SwitchType.appUninstaller.barInfo().controlType == .Switch)
        #expect(BuiltInSwitchCatalog.section(for: .appUninstaller) == .cleanupAndStorage)
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.showAppUninstallerTab))
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.didInstallAppUninstallerSwitch))
    }

    @Test func sectionVisibilityAppendsUninstallerAndPreservesExistingOrderAndIcon() {
        let hidden = SectionBar.sections(authenticator: false, soundMixer: false, systemMonitor: false, codexUsage: false, xcodeCleaner: false, appUninstaller: false)
        let shown = SectionBar.sections(authenticator: true, soundMixer: true, systemMonitor: true, codexUsage: true, claudeUsage: true, aphrodite: true, xcodeCleaner: true, appUninstaller: true)
        #expect(hidden == [.controls])
        #expect(shown == [.controls, .authenticator, .soundMixer, .systemMonitor, .codexUsage, .claudeUsage, .aphrodite, .xcodeCleaner, .appUninstaller])
        #expect(SectionBar.Section.appUninstaller.symbolName == "trash.fill")
        #expect(SectionBar.Section.appUninstaller.assetName == nil)
        #expect(!SectionBar.Section.appUninstaller.title.isEmpty)
    }

    @Test func hidingSelectedUninstallerReturnsOnlyControlToControls() async {
        let store = TestStore(initialState: OnlyControlReducer.State(selectedSection: .appUninstaller)) { OnlyControlReducer() }
        await store.send(.availableSectionsChanged([.controls])) { $0.selectedSection = .controls }
    }

    @Test func uninstallerOutsideClickKeepsShownPopoverOpen() {
        let popover = UninstallerPopoverSpy()
        let controller = StatusBarController(popover, appearance: { .single }, configuresSystemIntegrations: false)
        controller.listPreventsOutsideClickDismissal = true

        controller.mouseEventHandler(nil)

        #expect(popover.isShown)
        #expect(popover.closeCount == 0)
    }

    @Test func switchingToAnotherTabRestoresActualOutsideClickClosure() {
        let popover = UninstallerPopoverSpy()
        let controller = StatusBarController(popover, appearance: { .single }, configuresSystemIntegrations: false)
        controller.listPreventsOutsideClickDismissal = true
        controller.mouseEventHandler(nil)
        #expect(popover.closeCount == 0)

        controller.listPreventsOutsideClickDismissal = false
        controller.mouseEventHandler(nil)

        #expect(!popover.isShown)
        #expect(popover.closeCount == 1)
    }

    @Test func explicitHideStillClosesUninstallerPopover() {
        let popover = UninstallerPopoverSpy()
        let controller = StatusBarController(popover, appearance: { .single }, configuresSystemIntegrations: false)
        controller.listPreventsOutsideClickDismissal = true

        controller.hidePopover(nil)

        #expect(!popover.isShown)
        #expect(popover.closeCount == 1)
    }

    @Test func onlyUninstallerRetainsPanelForExternalAppDragging() {
        for section in SectionBar.Section.allCases {
            #expect(section.allowsOutsideClickDismissal == (section != .appUninstaller))
        }
    }

    @Test func leavingUninstallerRestoresOutsideClickDismissal() async {
        let store = TestStore(initialState: OnlyControlReducer.State(selectedSection: .appUninstaller)) { OnlyControlReducer() }
        #expect(!store.state.selectedSection.allowsOutsideClickDismissal)
        await store.send(.selectedSectionChanged(.controls)) { $0.selectedSection = .controls }
        #expect(store.state.selectedSection.allowsOutsideClickDismissal)
    }

    @Test func hidingUninstallerRestoresNormalOutsideClickDismissal() async {
        let store = TestStore(initialState: OnlyControlReducer.State(selectedSection: .appUninstaller)) { OnlyControlReducer() }
        #expect(!store.state.selectedSection.allowsOutsideClickDismissal)
        await store.send(.availableSectionsChanged([.controls])) { $0.selectedSection = .controls }
        #expect(store.state.selectedSection.allowsOutsideClickDismissal)
    }

    @Test func uninstallerIsExcludedFromRemoteCatalogAndForgedStatusLookup() async throws {
        let provider = RemoteCatalogProvider(
            builtIns: { [.appUninstaller] },
            makeBuiltIn: { _ in AppUninstallerSwitch(visibility: { true }, setVisibility: { _ in Issue.record("Remote catalog must not instantiate uninstaller") }, notifySettingsChanged: {}) },
            shortcutNames: { [] }, evolutions: { [] }
        )
        #expect(try await provider.catalog().isEmpty)
        do {
            _ = try await provider.status(.init(kind: .builtIn, value: "140737488355328"), 1)
            Issue.record("A local uninstaller must not expose remote status")
        } catch let error as RemoteProtocolError {
            #expect(error.code == .controlNotFound)
        }
    }

    @Test func forgedRemoteUninstallerCommandCannotOperateLocalVisibility() async {
        var writes = 0
        let uninstaller = AppUninstallerSwitch(visibility: { true }, setVisibility: { _ in writes += 1 }, notifySettingsChanged: {})
        let router = RemoteCommandRouter(resolveBuiltIn: { _ in uninstaller })
        let result = await router.perform(.init(requestID: UUID(), controlID: .init(kind: .builtIn, value: "140737488355328"), action: .setState(false)))
        guard case let .failure(error) = result.result else { Issue.record("Forged local-only command succeeded"); return }
        #expect(error.code == .controlNotFound)
        #expect(writes == 0)
    }
}

@MainActor
private final class UninstallerPopoverSpy: NSPopover {
    private var simulatedIsShown = true
    private(set) var closeCount = 0

    override var isShown: Bool { simulatedIsShown }

    override func performClose(_ sender: Any?) {
        closeCount += 1
        simulatedIsShown = false
    }
}
