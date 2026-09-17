import ComposableArchitecture
import Testing
@testable import OnlySwitch

@MainActor
struct OnlyRemoteCampaignFeatureTests {
    @Test
    func launchPresentsCampaignWhenCurrentVersionHasNotBeenAcknowledged() async {
        let recorder = OnlyRemoteCampaignRecorder(
            currentVersion: "3.1.0",
            acknowledgedVersion: nil
        )
        let store = TestStore(initialState: OnlyRemoteCampaignFeature.State()) {
            OnlyRemoteCampaignFeature()
        } withDependencies: {
            $0.onlyRemoteCampaign = recorder.client
        }

        await store.send(.launch(forcePresentation: false)) {
            $0.isPresented = true
        }

        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func launchDoesNotPresentCampaignWhenCurrentVersionWasAlreadyAcknowledged() async {
        let recorder = OnlyRemoteCampaignRecorder(
            currentVersion: "3.1.0",
            acknowledgedVersion: "3.1.0"
        )
        let store = TestStore(initialState: OnlyRemoteCampaignFeature.State()) {
            OnlyRemoteCampaignFeature()
        } withDependencies: {
            $0.onlyRemoteCampaign = recorder.client
        }

        await store.send(.launch(forcePresentation: false))

        #expect(store.state.isPresented == false)
        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func forcedLaunchPresentsCampaignWhenCurrentVersionWasAlreadyAcknowledged() async {
        let recorder = OnlyRemoteCampaignRecorder(
            currentVersion: "3.1.0",
            acknowledgedVersion: "3.1.0"
        )
        let store = TestStore(initialState: OnlyRemoteCampaignFeature.State()) {
            OnlyRemoteCampaignFeature()
        } withDependencies: {
            $0.onlyRemoteCampaign = recorder.client
        }

        await store.send(.launch(forcePresentation: true)) {
            $0.isPresented = true
        }

        #expect(await recorder.acknowledgedVersions.isEmpty)
    }

    @Test
    func dismissMarksCurrentVersionAndHidesCampaign() async {
        let recorder = OnlyRemoteCampaignRecorder(
            currentVersion: "3.1.0",
            acknowledgedVersion: nil
        )
        let store = TestStore(initialState: .init(isPresented: true)) {
            OnlyRemoteCampaignFeature()
        } withDependencies: {
            $0.onlyRemoteCampaign = recorder.client
        }

        await store.send(.dismissTapped) {
            $0.isPresented = false
        }
        await store.finish()

        #expect(await recorder.acknowledgedVersions == ["3.1.0"])
        #expect(await recorder.appStoreOpenCount == 0)
        #expect(await recorder.remoteAccessSettingsOpenCount == 0)
    }

    @Test
    func downloadMarksCurrentVersionHidesCampaignAndOpensAppStore() async {
        let recorder = OnlyRemoteCampaignRecorder(
            currentVersion: "3.1.0",
            acknowledgedVersion: nil
        )
        let store = TestStore(initialState: .init(isPresented: true)) {
            OnlyRemoteCampaignFeature()
        } withDependencies: {
            $0.onlyRemoteCampaign = recorder.client
        }

        await store.send(.downloadTapped) {
            $0.isPresented = false
        }
        await store.finish()

        #expect(await recorder.acknowledgedVersions == ["3.1.0"])
        #expect(await recorder.appStoreOpenCount == 1)
        #expect(await recorder.remoteAccessSettingsOpenCount == 0)
    }

    @Test
    func remoteAccessSettingsMarksCurrentVersionHidesCampaignAndOpensSettings() async {
        let recorder = OnlyRemoteCampaignRecorder(
            currentVersion: "3.1.0",
            acknowledgedVersion: nil
        )
        let store = TestStore(initialState: .init(isPresented: true)) {
            OnlyRemoteCampaignFeature()
        } withDependencies: {
            $0.onlyRemoteCampaign = recorder.client
        }

        await store.send(.openRemoteAccessSettingsTapped) {
            $0.isPresented = false
            $0.isOpeningRemoteAccessSettings = true
        }
        await store.finish()

        #expect(await recorder.acknowledgedVersions == ["3.1.0"])
        #expect(await recorder.appStoreOpenCount == 0)
        #expect(await recorder.remoteAccessSettingsOpenCount == 1)
    }

    @Test
    func actionsAfterTheCampaignHasClosedDoNotRepeatSideEffects() async {
        let recorder = OnlyRemoteCampaignRecorder(
            currentVersion: "3.1.0",
            acknowledgedVersion: nil
        )
        let store = TestStore(initialState: .init()) {
            OnlyRemoteCampaignFeature()
        } withDependencies: {
            $0.onlyRemoteCampaign = recorder.client
        }

        await store.send(.downloadTapped)
        await store.send(.openRemoteAccessSettingsTapped)
        await store.send(.dismissTapped)
        await store.finish()

        #expect(await recorder.acknowledgedVersions.isEmpty)
        #expect(await recorder.appStoreOpenCount == 0)
        #expect(await recorder.remoteAccessSettingsOpenCount == 0)
    }
}

private actor OnlyRemoteCampaignRecorder {
    nonisolated let currentVersion: String
    nonisolated let acknowledgedVersion: String?

    private(set) var acknowledgedVersions: [String] = []
    private(set) var appStoreOpenCount = 0
    private(set) var remoteAccessSettingsOpenCount = 0

    init(currentVersion: String, acknowledgedVersion: String?) {
        self.currentVersion = currentVersion
        self.acknowledgedVersion = acknowledgedVersion
    }

    nonisolated var client: OnlyRemoteCampaignClient {
        OnlyRemoteCampaignClient(
            currentVersion: { self.currentVersion },
            acknowledgedVersion: { self.acknowledgedVersion },
            markAcknowledged: { version in await self.markAcknowledged(version) },
            openAppStore: { await self.openAppStore() },
            openRemoteAccessSettings: { await self.openRemoteAccessSettings() }
        )
    }

    private func markAcknowledged(_ version: String) {
        acknowledgedVersions.append(version)
    }

    private func openAppStore() {
        appStoreOpenCount += 1
    }

    private func openRemoteAccessSettings() {
        remoteAccessSettingsOpenCount += 1
    }
}
