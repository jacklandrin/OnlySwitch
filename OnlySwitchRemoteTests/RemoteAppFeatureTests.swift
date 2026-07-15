import ComposableArchitecture
import Foundation
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteAppFeatureTests {
    private let studio = PairedMac(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        displayName: "Studio",
        lastEndpointDescription: nil,
        lastConnectedAt: nil,
        requiresPairing: false
    )
    private let laptop = PairedMac(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
        displayName: "Laptop",
        lastEndpointDescription: nil,
        lastConnectedAt: nil,
        requiresPairing: false
    )

    @Test func firstLaunchPushesRequiredSettings() async {
        let store = TestStore(initialState: RemoteAppFeature.State()) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [] }
            $0.remotePersistence.loadSelectedMacID = { nil }
            $0.remoteConnection.select = { _ in }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task) {
            $0.loadGeneration = 1
            $0.isLoading = true
        }
        await store.receive(.launchResponse(1, .init(pairedMacs: [], selectedMacID: nil))) {
            $0.isLoading = false
        }
        #expect(store.state.path.count == 1)
        guard case let .settings(settings)? = store.state.path.last else {
            Issue.record("Expected required Settings")
            return
        }
        #expect(settings.isSetupRequired)
    }

    @Test func persistedSelectionShowsDashboardAndSelectsThatMac() async {
        let selected = SelectionRecorder()
        let studio = studio
        let laptop = laptop
        let store = TestStore(initialState: RemoteAppFeature.State()) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [studio, laptop] }
            $0.remotePersistence.loadSelectedMacID = { laptop.id }
            $0.remoteConnection.select = { await selected.record($0) }
        }

        await store.send(.task) {
            $0.loadGeneration = 1
            $0.isLoading = true
        }
        await store.receive(.launchResponse(1, .init(pairedMacs: [studio, laptop], selectedMacID: laptop.id))) {
            $0.isLoading = false
            $0.pairedMacs = [studio, laptop]
            $0.selectedMacID = laptop.id
        }
        await store.finish()
        #expect(await selected.ids == [laptop.id])
    }

    @Test func invalidPersistedSelectionFallsBackToFirstMacAndPersistsIt() async {
        let saved = SelectionRecorder()
        let selected = SelectionRecorder()
        let studio = studio
        let staleID = UUID(uuidString: "00000000-0000-0000-0000-000000000199")!
        let store = TestStore(initialState: RemoteAppFeature.State()) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [studio] }
            $0.remotePersistence.loadSelectedMacID = { staleID }
            $0.remotePersistence.saveSelectedMacID = { await saved.recordID($0) }
            $0.remoteConnection.select = { await selected.record($0) }
        }

        await store.send(.task) {
            $0.loadGeneration = 1
            $0.isLoading = true
        }
        await store.receive(.launchResponse(1, .init(pairedMacs: [studio], selectedMacID: staleID))) {
            $0.isLoading = false
            $0.pairedMacs = [studio]
            $0.selectedMacID = studio.id
        }
        await store.finish()
        #expect(await saved.ids == [studio.id])
        #expect(await selected.ids == [studio.id])
    }

    @Test func hamburgerPushesDismissibleSettings() async throws {
        var state = RemoteAppFeature.State()
        state.pairedMacs = [studio]
        state.selectedMacID = studio.id
        let store = TestStore(initialState: state) { RemoteAppFeature() }

        await store.send(.settingsButtonTapped) {
            $0.path.append(.settings(.init(
                isSetupRequired: false,
                pairedMacs: [studio],
                selectedMacID: studio.id
            )))
        }
        let settings = try #require(store.state.path.last)
        guard case let .settings(settingsState) = settings else {
            Issue.record("Expected Settings on the navigation stack")
            return
        }
        #expect(settingsState.isSetupRequired == false)
    }

    @Test func requiredSettingsCannotBePopped() async throws {
        var state = RemoteAppFeature.State()
        state.path.append(.settings(.init(isSetupRequired: true)))
        let id = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) { RemoteAppFeature() }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.path(.popFrom(id: id)))
        #expect(store.state.path.count == 1)
        guard case let .settings(settings)? = store.state.path.last else {
            Issue.record("Expected required Settings")
            return
        }
        #expect(settings.isSetupRequired)
    }

    @Test func pairingSuccessPopsRequiredSettingsAndPersistsSelection() async throws {
        var state = RemoteAppFeature.State()
        state.path.append(.settings(.init(isSetupRequired: true)))
        let id = try #require(state.path.ids.last)
        let saved = SelectionRecorder()
        let selected = SelectionRecorder()
        let studio = studio
        let store = TestStore(initialState: state) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.saveSelectedMacID = { await saved.recordID($0) }
            $0.remoteConnection.select = { await selected.record($0) }
        }

        await store.send(.path(.element(id: id, action: .settings(.delegate(.paired(studio)))))) {
            $0.pairedMacs = [studio]
            $0.selectedMacID = studio.id
            $0.path.removeAll()
        }
        await store.finish()
        #expect(await saved.ids == [studio.id])
        #expect(await selected.ids == [studio.id])
    }

    @Test func removingFinalMacReturnsToRequiredSettings() async throws {
        var state = RemoteAppFeature.State()
        state.pairedMacs = [studio]
        state.selectedMacID = studio.id
        state.path.append(.settings(.init(
            isSetupRequired: false,
            pairedMacs: [studio],
            selectedMacID: studio.id
        )))
        let id = try #require(state.path.ids.last)
        let saved = SelectionRecorder()
        let selected = SelectionRecorder()
        let store = TestStore(initialState: state) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.saveSelectedMacID = { await saved.recordID($0) }
            $0.remoteConnection.select = { await selected.record($0) }
        }

        await store.send(.path(.element(id: id, action: .settings(.delegate(.allMacsRemoved))))) {
            $0.pairedMacs = []
            $0.selectedMacID = nil
            $0.path.removeAll()
            $0.path.append(.settings(.init(isSetupRequired: true)))
        }
        await store.finish()
        #expect(await saved.ids == [nil])
        #expect(await selected.ids == [nil])
    }

    @Test func staleLaunchResponseIsIgnored() async {
        var state = RemoteAppFeature.State()
        state.loadGeneration = 2
        state.isLoading = true
        let store = TestStore(initialState: state) { RemoteAppFeature() }

        await store.send(.launchResponse(1, .init(pairedMacs: [studio], selectedMacID: studio.id)))
        #expect(store.state.pairedMacs.isEmpty)
        #expect(store.state.isLoading)
    }

    @Test func sceneLifecycleForwardsLatestForegroundState() async {
        let recorder = ForegroundRecorder()
        let store = TestStore(initialState: RemoteAppFeature.State()) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remoteConnection.setForegrounded = { await recorder.record($0) }
        }

        await store.send(.scenePhaseChanged(false)) {
            $0.isForegrounded = false
            $0.lifecycleGeneration = 1
        }
        await store.receive(.lifecycleResponse(1))
        await store.send(.scenePhaseChanged(true)) {
            $0.isForegrounded = true
            $0.lifecycleGeneration = 2
        }
        await store.receive(.lifecycleResponse(2))
        #expect(await recorder.values == [false, true])
    }
}

private actor SelectionRecorder {
    private(set) var ids: [UUID?] = []

    func record(_ mac: PairedMac?) { ids.append(mac?.id) }
    func recordID(_ id: UUID?) { ids.append(id) }
}

private actor ForegroundRecorder {
    private(set) var values: [Bool] = []
    func record(_ value: Bool) { values.append(value) }
}
