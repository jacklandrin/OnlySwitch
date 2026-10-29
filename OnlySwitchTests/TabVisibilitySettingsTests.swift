import Defines
import Extensions
import Foundation
import RemoteCore
import Switches
import Testing
@testable import OnlySwitch

@MainActor
struct TabVisibilitySettingsTests {
    @Test func everyOptionalTabIsManageableAndControlsIsNot() {
        #expect(SectionBar.Section.manageable == SectionBar.Section.allCases.filter { $0 != .controls })
        #expect(!SectionBar.Section.manageable.contains(.controls))
        #expect(SectionBar.Section.manageable.count == 9)
    }

    @Test func tabsBackedByDefaultsUseTheExistingSharedKeys() {
        #expect(SectionBar.Section.systemMonitor.visibilityDefaultsKey == UserDefaults.Key.showSystemMonitorTab)
        #expect(SectionBar.Section.codexUsage.visibilityDefaultsKey == UserDefaults.Key.showCodexUsageTab)
        #expect(SectionBar.Section.claudeUsage.visibilityDefaultsKey == UserDefaults.Key.showClaudeUsageTab)
        #expect(SectionBar.Section.aphrodite.visibilityDefaultsKey == UserDefaults.Key.showAphroditeTab)
        #expect(SectionBar.Section.xcodeCleaner.visibilityDefaultsKey == UserDefaults.Key.showXcodeCleanerTab)
        #expect(SectionBar.Section.appUninstaller.visibilityDefaultsKey == UserDefaults.Key.showAppUninstallerTab)
        #expect(SectionBar.Section.screenshots.visibilityDefaultsKey == UserDefaults.Key.showScreenshotsTab)
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

    @Test func tabsSettingsPageFollowsBuiltIn() {
        let items = SettingsItem.allCases
        #expect(items.firstIndex(of: .Tabs) == items.firstIndex(of: .Customize).map { $0 + 1 })
    }
}
