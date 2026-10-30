import Foundation
import ComposableArchitecture
import Testing
@testable import OnlySwitchRemote

@MainActor
struct GlobalSettingsMembershipTests {
    @Test func membershipEmitsDelegateWithoutChangingRequiredSetup() async {
        let store = TestStore(initialState: GlobalSettingsFeature.State(isSetupRequired: true)) { GlobalSettingsFeature() }
        let originalState = store.state
        await store.send(.membershipTapped)
        await store.receive(.delegate(.openMembership))
        #expect(store.state == originalState)
    }
}

@MainActor
struct GlobalSettingsTabTests {
    @Test func tabTogglesAreIndependentAndSaveInOrder() async {
        let saved = LockIsolated<[RemoteTabConfiguration]>([])
        let store = TestStore(initialState: GlobalSettingsFeature.State(tabConfiguration: .init())) {
            GlobalSettingsFeature()
        } withDependencies: {
            $0.remoteTabPreferences.save = { configuration in saved.withValue { $0.append(configuration) } }
        }
        var expected = RemoteTabConfiguration()
        for page in [RemoteAppPage.systemMonitor, .codexUsage, .claudeUsage] {
            expected.setVisibility(false, for: page)
            let configuration = expected
            await store.send(.tabVisibilityChanged(page, false)) { $0.tabConfiguration = configuration }
            await store.receive(.delegate(.tabConfigurationChanged(configuration)))
        }
        #expect(saved.value.count == 3)
        #expect(saved.value.first == .init(showsSystemMonitor: false))
        #expect(saved.value.last == expected)
        #expect(expected.visiblePages == [.controls, .soundMixer, .brightness, .aphrodite])
        await store.send(.tabVisibilityChanged(.codexUsage, true)) { $0.tabConfiguration.showsCodexUsage = true }
        expected.showsCodexUsage = true
        await store.receive(.delegate(.tabConfigurationChanged(expected)))
        #expect(saved.value.last == expected)
        #expect(expected.visiblePages == [.controls, .soundMixer, .brightness, .codexUsage, .aphrodite])
    }

    @Test func controlsCannotBeHidden() async {
        let saved = LockIsolated<[RemoteTabConfiguration]>([])
        let store = TestStore(initialState: GlobalSettingsFeature.State(tabConfiguration: .init())) {
            GlobalSettingsFeature()
        } withDependencies: {
            $0.remoteTabPreferences.save = { configuration in saved.withValue { $0.append(configuration) } }
        }
        await store.send(.tabVisibilityChanged(.controls, false))
        #expect(saved.value.isEmpty)
        #expect(store.state.tabConfiguration.isVisible(.controls))
    }

    @Test func unchangedVisibilityDoesNotSaveOrNotify() async {
        let saved = LockIsolated<[RemoteTabConfiguration]>([])
        let store = TestStore(initialState: GlobalSettingsFeature.State(tabConfiguration: .init())) {
            GlobalSettingsFeature()
        } withDependencies: {
            $0.remoteTabPreferences.save = { configuration in saved.withValue { $0.append(configuration) } }
        }
        await store.send(.tabVisibilityChanged(.brightness, true))
        #expect(saved.value.isEmpty)
    }

    @Test(arguments: [RemoteAppPage.soundMixer, .brightness, .aphrodite])
    func plusTabsCanBeHidden(page: RemoteAppPage) async {
        let saved = LockIsolated<[RemoteTabConfiguration]>([])
        let store = TestStore(initialState: GlobalSettingsFeature.State(tabConfiguration: .init())) {
            GlobalSettingsFeature()
        } withDependencies: {
            $0.remoteTabPreferences.save = { configuration in saved.withValue { $0.append(configuration) } }
        }
        var expected = RemoteTabConfiguration()
        expected.setVisibility(false, for: page)
        let configuration = expected
        await store.send(.tabVisibilityChanged(page, false)) { $0.tabConfiguration = configuration }
        await store.receive(.delegate(.tabConfigurationChanged(configuration)))
        #expect(saved.value == [configuration])
        #expect(configuration.visiblePages.contains(page) == false)
    }

    @Test func preferencesDefaultToVisibleAndReloadSavedChoices() throws {
        let suite = "RemoteTabPreferencesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RemoteTabPreferencesClient.preferenceSeed(defaults: defaults) == .init())
        defaults.set(false, forKey: "tabs.showsSystemMonitor")
        #expect(RemoteTabPreferencesClient.preferenceSeed(defaults: defaults) == .init(showsSystemMonitor: false))
        let configuration = RemoteTabConfiguration(showsSystemMonitor: true, showsCodexUsage: false, showsClaudeUsage: false)
        RemoteTabPreferencesClient.save(configuration, defaults: defaults)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(RemoteTabPreferencesClient.preferenceSeed(defaults: reopened) == configuration)
    }
}
