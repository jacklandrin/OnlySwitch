import Combine
import Defines
import ComposableArchitecture
import Extensions
import Foundation
import RemoteCore
import Switches
import Testing
@testable import AppFeature

@MainActor
struct TabVisibilitySettingsTests {
    @Test func everyOptionalTabIsManageableAndControlsIsNot() {
        #expect(SectionBar.Section.manageable == SectionBar.Section.allCases.filter { $0 != .controls })
        #expect(!SectionBar.Section.manageable.contains(.controls))
        #expect(SectionBar.Section.manageable.count == 11)
    }

    @Test func tabsBackedByDefaultsUseTheExistingSharedKeys() {
        #expect(SectionBar.Section.brightness.visibilityDefaultsKey == UserDefaults.Key.showBrightnessTab)
        #expect(SectionBar.Section.systemMonitor.visibilityDefaultsKey == UserDefaults.Key.showSystemMonitorTab)
        #expect(SectionBar.Section.codexUsage.visibilityDefaultsKey == UserDefaults.Key.showCodexUsageTab)
        #expect(SectionBar.Section.claudeUsage.visibilityDefaultsKey == UserDefaults.Key.showClaudeUsageTab)
        #expect(SectionBar.Section.aphrodite.visibilityDefaultsKey == UserDefaults.Key.showAphroditeTab)
        #expect(SectionBar.Section.xcodeCleaner.visibilityDefaultsKey == UserDefaults.Key.showXcodeCleanerTab)
        #expect(SectionBar.Section.appUninstaller.visibilityDefaultsKey == UserDefaults.Key.showAppUninstallerTab)
        #expect(SectionBar.Section.screenshots.visibilityDefaultsKey == UserDefaults.Key.showScreenshotsTab)
        #expect(SectionBar.Section.schedules.visibilityDefaultsKey == UserDefaults.Key.showSchedulesTab)
        #expect(SectionBar.Section.authenticator.visibilityDefaultsKey == nil)
        #expect(SectionBar.Section.soundMixer.visibilityDefaultsKey == nil)
    }

    @Test func defaultsClientTreatsMissingValuesAsVisibleAndRoutesFeatureFlags() throws {
        let suite = "TabVisibilitySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var authenticator = false
        var soundMixer = true
        let client = TabVisibilityClient.defaults(
            defaults,
            authenticatorEnabled: { authenticator },
            setAuthenticatorEnabled: { authenticator = $0 },
            soundMixerEnabled: { soundMixer },
            setSoundMixerEnabled: { soundMixer = $0 }
        )

        #expect(client.isVisible(.controls))
        #expect(client.isVisible(.xcodeCleaner))
        #expect(!client.isVisible(.authenticator))
        #expect(client.isVisible(.soundMixer))

        client.setVisible(false, .xcodeCleaner)
        client.setVisible(true, .authenticator)
        client.setVisible(false, .soundMixer)
        client.setVisible(false, .controls)

        #expect(defaults.object(forKey: "showXcodeCleanerTabKey") as? Bool == false)
        #expect(defaults.object(forKey: "showScreenshotsTabKey") == nil)
        #expect(authenticator)
        #expect(!soundMixer)
        #expect(client.isVisible(.controls))
    }

    @Test func viewModelWritesThroughClientAndPostsOneSettingsRefresh() {
        var stored: [SectionBar.Section: Bool] = [.screenshots: false]
        let center = NotificationCenter()
        let notifications = TestMutex(0)
        let observer = center.addObserver(forName: .changeSettings, object: nil, queue: nil) { _ in notifications.withLock { $0 += 1 } }
        defer { center.removeObserver(observer) }
        let viewModel = TabVisibilitySettingsVM(
            client: TabVisibilityClient(isVisible: { stored[$0] ?? true }, setVisible: { stored[$1] = $0 }),
            notificationCenter: center
        )

        #expect(!viewModel.isVisible(.screenshots))
        #expect(viewModel.isVisible(.systemMonitor))

        viewModel.setVisible(true, for: .screenshots)
        #expect(stored[.screenshots] == true)
        #expect(viewModel.isVisible(.screenshots))
        #expect(notifications.withLock { $0 } == 1)

        viewModel.setVisible(true, for: .screenshots)
        #expect(notifications.withLock { $0 } == 1)
    }

    @Test func viewModelReloadsWhenAnotherScreenChangesATab() {
        var stored: [SectionBar.Section: Bool] = [:]
        let center = NotificationCenter()
        let viewModel = TabVisibilitySettingsVM(
            client: TabVisibilityClient(isVisible: { stored[$0] ?? true }, setVisible: { stored[$1] = $0 }),
            notificationCenter: center
        )
        stored[.authenticator] = false
        viewModel.reload()
        #expect(!viewModel.isVisible(.authenticator))
    }

    @Test func unrelatedSettingsChangesDoNotRepublishTheTabsPage() {
        let viewModel = TabVisibilitySettingsVM(
            client: TabVisibilityClient(isVisible: { _ in true }, setVisible: { _, _ in }),
            notificationCenter: NotificationCenter()
        )
        var publishes = 0
        let cancellable = viewModel.objectWillChange.sink { publishes += 1 }
        defer { cancellable.cancel() }

        viewModel.reload()
        viewModel.reload()

        #expect(publishes == 0)
    }

    @Test func tabVisibilitySwitchesAreDeprecatedButKeepStableIdentifiers() {
        let deprecated: Set<SwitchType> = [
            .authenticator, .soundMixer, .systemMonitor, .codexUsage,
            .claudeUsage, .aphrodite, .xcodeCleaner, .appUninstaller,
        ]
        #expect(SwitchType.deprecatedTabVisibilitySwitches == deprecated)
        #expect(SwitchType.offeredCases.allSatisfy { !deprecated.contains($0) })
        #expect(SwitchType.offeredCases.count == SwitchType.allCases.count - deprecated.count)
        #expect(SwitchType.offeredCases.contains(.tailscale))
        for type in deprecated {
            #expect(SwitchType(legacyIdentifier: type.legacyIdentifier) == type)
        }
    }

    @Test func deprecatedSwitchesAreNotOfferedInSwitchListOrCustomize() {
        #expect(SwitchManager.shared.visibleSwitchTypes().isDisjoint(with: SwitchType.deprecatedTabVisibilitySwitches))
        #expect(CustomizeVM.shared.allSwitches.allSatisfy { !$0.type.isDeprecatedTabVisibilitySwitch })
    }

    @Test func liveRemoteRouterRejectsDeprecatedTabSwitches() async {
        let router = RemoteCommandRouter.live
        let id = String(SwitchType.claudeUsage.legacyIdentifier)
        let result = await router.perform(.init(requestID: UUID(), controlID: .init(kind: .builtIn, value: id), action: .setState(false)))
        guard case let .failure(error) = result.result else { Issue.record("Deprecated tab switch was operated remotely"); return }
        #expect(error.code == .controlNotFound)
    }

    @Test func brightnessTabUsesSharedVisibilityAndDefaultsToVisible() throws {
        let suite = "BrightnessTabTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TabVisibilityClient.defaults(defaults,
            authenticatorEnabled: { false }, setAuthenticatorEnabled: { _ in },
            soundMixerEnabled: { false }, setSoundMixerEnabled: { _ in })
        #expect(client.isVisible(.brightness))
        client.setVisible(false, .brightness)
        #expect(defaults.object(forKey: UserDefaults.Key.showBrightnessTab) as? Bool == false)
        let hidden = SectionBar.sections(authenticator: false, soundMixer: false,
            systemMonitor: false, codexUsage: false, brightness: client.isVisible(.brightness))
        #expect(hidden == [.controls])
        client.setVisible(true, .brightness)
        #expect(SectionBar.sections(authenticator: false, soundMixer: false,
            systemMonitor: false, codexUsage: false, brightness: client.isVisible(.brightness)) == [.controls, .brightness])
    }

    @Test func hidingSelectedBrightnessReturnsOnlyControlToControls() async {
        let store = TestStore(initialState: OnlyControlReducer.State(selectedSection: .brightness)) {
            OnlyControlReducer()
        }
        await store.send(.availableSectionsChanged([.controls])) { $0.selectedSection = .controls }
    }

    @Test func schedulesTabUsesSharedVisibilityAndDefaultsToVisible() throws {
        let suite = "SchedulesTabTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TabVisibilityClient.defaults(defaults,
            authenticatorEnabled: { false }, setAuthenticatorEnabled: { _ in },
            soundMixerEnabled: { false }, setSoundMixerEnabled: { _ in })
        #expect(client.isVisible(.schedules))
        client.setVisible(false, .schedules)
        #expect(defaults.object(forKey: UserDefaults.Key.showSchedulesTab) as? Bool == false)
        #expect(SectionBar.sections(authenticator: false, soundMixer: false,
            systemMonitor: false, codexUsage: false, schedules: client.isVisible(.schedules)) == [.controls])
        client.setVisible(true, .schedules)
        #expect(SectionBar.sections(authenticator: false, soundMixer: false,
            systemMonitor: false, codexUsage: false, schedules: client.isVisible(.schedules)) == [.controls, .schedules])
    }

    @Test func schedulesTabIsLastAndUsesItsSymbol() {
        let all = SectionBar.sections(authenticator: true, soundMixer: true, systemMonitor: true, codexUsage: true,
            claudeUsage: true, aphrodite: true, xcodeCleaner: true, appUninstaller: true, screenshots: true,
            brightness: true, schedules: true)
        #expect(all.last == .schedules)
        #expect(all.count == SectionBar.Section.allCases.count)
        #expect(SectionBar.Section.schedules.symbolName == "calendar.badge.clock")
        #expect(SectionBar.Section.schedules.assetName == nil)
        #expect(SectionBar.Section.schedules.allowsOutsideClickDismissal)
    }

    @Test func scheduleVisibilityIsExportedButTheScheduleListIsNot() {
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.showSchedulesTab))
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.schedules))
    }

    @Test func schedulesSettingsPageFollowsEvolution() {
        let items = SettingsItem.allCases
        #expect(items.firstIndex(of: .Schedules) == items.firstIndex(of: .Evolution).map { $0 + 1 })
    }

    @Test func savedTabOrderIsSanitizedAndNewTabsAreAppended() {
        #expect(SectionBar.manageableOrder(from: "") == SectionBar.Section.manageable)
        let order = SectionBar.manageableOrder(from: "schedules,controls,unknown,brightness,schedules")
        #expect(order.prefix(2) == [.schedules, .brightness])
        #expect(order.count == SectionBar.Section.manageable.count)
        #expect(Set(order) == Set(SectionBar.Section.manageable))
        #expect(Array(order.dropFirst(2)) == SectionBar.Section.manageable.filter { $0 != .schedules && $0 != .brightness })
        #expect(SectionBar.manageableOrder(from: SectionBar.storedOrder(order)) == order)
    }

    @Test func sectionsFollowTheSavedOrderWithControlsFirst() {
        let order = SectionBar.manageableOrder(from: "schedules,soundMixer,authenticator")
        let sections = SectionBar.sections(authenticator: true, soundMixer: true, systemMonitor: false,
            codexUsage: false, schedules: true, order: order)
        #expect(sections == [.controls, .schedules, .soundMixer, .authenticator])
    }

    @Test func defaultsClientPersistsTabOrderUnderTheExportedKey() throws {
        let suite = "TabOrderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TabVisibilityClient.defaults(defaults,
            authenticatorEnabled: { false }, setAuthenticatorEnabled: { _ in },
            soundMixerEnabled: { false }, setSoundMixerEnabled: { _ in })
        #expect(client.order() == SectionBar.Section.manageable)
        let reversed = Array(SectionBar.Section.manageable.reversed())
        client.setOrder(reversed)
        #expect(client.order() == reversed)
        #expect(defaults.string(forKey: UserDefaults.Key.tabOrder) == SectionBar.storedOrder(reversed))
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.tabOrder))
    }

    @Test func viewModelReordersTabsAndPostsOneSettingsRefresh() {
        var stored = SectionBar.Section.manageable
        let center = NotificationCenter()
        let notifications = TestMutex(0)
        let observer = center.addObserver(forName: .changeSettings, object: nil, queue: nil) { _ in notifications.withLock { $0 += 1 } }
        defer { center.removeObserver(observer) }
        let viewModel = TabVisibilitySettingsVM(
            client: TabVisibilityClient(isVisible: { _ in true }, setVisible: { _, _ in },
                order: { stored }, setOrder: { stored = $0 }),
            notificationCenter: center
        )
        let first = stored[0], second = stored[1], last = stored[stored.count - 1]

        // onMove semantics: moving the first row below the second targets index 2.
        viewModel.move(fromOffsets: [0], toOffset: 2)
        #expect(Array(viewModel.sections.prefix(2)) == [second, first])
        #expect(stored == viewModel.sections)
        #expect(notifications.withLock { $0 } == 1)

        viewModel.move(fromOffsets: [0], toOffset: 0)
        #expect(notifications.withLock { $0 } == 1)

        #expect(!viewModel.canMove(second, by: -1))
        #expect(!viewModel.canMove(last, by: 1))
        viewModel.move(last, by: 1)
        #expect(viewModel.sections.last == last)

        viewModel.move(last, by: -1)
        #expect(viewModel.sections[viewModel.sections.count - 2] == last)
        viewModel.move(first, by: -1)
        #expect(Array(viewModel.sections.prefix(2)) == [first, second])
        #expect(notifications.withLock { $0 } == 3)
    }

    @Test func reorderModeTogglesAndDraggingOntoARowTakesItsPlace() {
        var stored = SectionBar.Section.manageable
        let viewModel = TabVisibilitySettingsVM(
            client: TabVisibilityClient(isVisible: { _ in true }, setVisible: { _, _ in },
                order: { stored }, setOrder: { stored = $0 }),
            notificationCenter: NotificationCenter()
        )
        #expect(!viewModel.isReordering)
        viewModel.toggleReordering()
        #expect(viewModel.isReordering)

        let initial = viewModel.sections
        viewModel.move(initial[0], onto: initial[3])
        #expect(Array(viewModel.sections.prefix(4)) == [initial[1], initial[2], initial[3], initial[0]])
        viewModel.move(initial[0], onto: initial[1])
        #expect(Array(viewModel.sections.prefix(4)) == [initial[0], initial[1], initial[2], initial[3]])
        #expect(stored == initial)

        viewModel.toggleReordering()
        #expect(!viewModel.isReordering)
    }

    @Test func tabsSettingsPageFollowsBuiltIn() {
        let items = SettingsItem.allCases
        #expect(items.firstIndex(of: .Tabs) == items.firstIndex(of: .Customize).map { $0 + 1 })
    }
}
