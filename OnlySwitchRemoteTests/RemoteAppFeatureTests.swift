import ComposableArchitecture
import Foundation
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteAppFeatureTests {
    private let studio = PairedMac(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, displayName: "Studio", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)
    private let laptop = PairedMac(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, displayName: "Laptop", lastEndpointDescription: nil, lastConnectedAt: nil, requiresPairing: false)

    @Test func firstLaunchHasRequiredSettingsBeforeAnyEffect() {
        let state = RemoteAppFeature.State(hasCompletedInitialSetup: false)
        #expect(state.requiredSettings?.isSetupRequired == true)
        #expect(state.path.isEmpty)
        #expect(state.hasCompletedInitialSetup == false)
    }

    @Test func completedLaunchStartsAtDashboardAndSelectsPersistedMac() async {
        let selected = SelectionRecorder(); let studio = studio; let laptop = laptop
        let store = TestStore(initialState: RemoteAppFeature.State(hasCompletedInitialSetup: true)) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [studio, laptop] }
            $0.remotePersistence.loadSelectedMacID = { laptop.id }
            $0.remoteConnection.select = { await selected.record($0) }
        }
        #expect(store.state.requiredSettings == nil)
        await store.send(.task) { $0.loadGeneration = 1; $0.isLoading = true }
        await store.receive(.launchResponse(1, .success(.init(pairedMacs: [studio, laptop], selectedMacID: laptop.id)))) {
            $0.isLoading = false; $0.pairedMacs = [studio, laptop]; $0.selectedMacID = laptop.id
        }
        await store.finish()
        #expect(await selected.ids == [laptop.id])
    }

    @Test func alreadyAuthenticatedSnapshotSeedsConnectedStateBeforeSettingsOpens() async {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio]
        state.selectedMacID = studio.id
        let store = TestStore(initialState: state) { RemoteAppFeature() }

        await store.send(.connectionSnapshotLoaded(.init(
            selectedMacID: studio.id,
            authenticatedMacID: studio.id
        ))) {
            $0.connectedMacIDs = [studio.id]
        }
        await store.send(.settingsButtonTapped) {
            $0.path.append(.settings(.init(
                isSetupRequired: false,
                pairedMacs: [studio],
                selectedMacID: studio.id,
                connectionStatuses: [studio.id: .connected]
            )))
        }
    }

    @Test func connectedStateFollowsTheSingleSelectedRuntimeSession() async throws {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio, laptop]
        state.selectedMacID = studio.id
        state.path.append(.settings(.init(
            isSetupRequired: false,
            pairedMacs: [studio, laptop],
            selectedMacID: studio.id
        )))
        let pathID = try #require(state.path.ids.last)
        let studioID = studio.id
        let laptopID = laptop.id
        let store = TestStore(initialState: state) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [studio, laptop] }
        }

        await store.send(.connectionSnapshotLoaded(.init(
            selectedMacID: studioID,
            authenticatedMacID: studioID
        ))) {
            $0.connectedMacIDs = [studioID]
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.connectionStatuses = [studioID: .connected]
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await store.send(.connectionEvent(.connecting(laptopID))) {
            $0.connectedMacIDs = []
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.connectionStatuses = [laptopID: .connecting]
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await store.send(.connectionEvent(.authenticated(laptopID))) {
            $0.connectedMacIDs = [laptopID]
            $0.metadataRefreshGeneration = 1
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.connectionStatuses = [laptopID: .connected]
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await store.receive(.pairedMetadataRefreshed(1, [studio, laptop]))
        await store.finish()

        var reopened = store.state
        reopened.path.removeAll()
        let reopenedStore = TestStore(initialState: reopened) { RemoteAppFeature() }
        await reopenedStore.send(.settingsButtonTapped) {
            $0.path.append(.settings(.init(
                isSetupRequired: false,
                pairedMacs: [studio, laptop],
                selectedMacID: studioID,
                connectionStatuses: [laptopID: .connected]
            )))
        }
    }

    @Test func revocationRefreshSurvivesSettingsDismissAndReopen() async throws {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio]
        state.selectedMacID = studio.id
        state.connectedMacIDs = [studio.id]
        state.path.append(.settings(.init(
            isSetupRequired: false,
            pairedMacs: [studio],
            selectedMacID: studio.id,
            connectionStatuses: [studio.id: .connected]
        )))
        let pathID = try #require(state.path.ids.last)
        let refreshed = PairedMac(
            id: studio.id,
            displayName: studio.displayName,
            lastEndpointDescription: studio.lastEndpointDescription,
            lastConnectedAt: studio.lastConnectedAt,
            requiresPairing: true
        )
        let store = TestStore(initialState: state) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [refreshed] }
        }

        await store.send(.connectionEvent(.revoked(studio.id))) {
            $0.connectedMacIDs = []
            $0.metadataRefreshGeneration = 1
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.connectionStatuses[studio.id] = .needsPairing
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await store.receive(.pairedMetadataRefreshed(1, [refreshed])) {
            $0.pairedMacs = [refreshed]
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.pairedMacs = [refreshed]
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await store.finish()

        var reopenedState = store.state
        reopenedState.path.removeAll()
        let reopenedStore = TestStore(initialState: reopenedState) { RemoteAppFeature() }
        await reopenedStore.send(.settingsButtonTapped) {
            $0.path.append(.settings(.init(
                isSetupRequired: false,
                pairedMacs: [refreshed],
                selectedMacID: studio.id,
                connectionStatuses: [studio.id: .needsPairing]
            )))
        }
    }

    @Test func staleMetadataRefreshCannotClobberNewlyPairedMacOrSettings() async throws {
        let gate = MetadataLoadGate(result: [studio])
        let persistence = PersistenceAttemptRecorder(shouldFail: false)
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio]
        state.selectedMacID = studio.id
        state.path.append(.settings(.init(isSetupRequired: false, pairedMacs: [studio], selectedMacID: studio.id)))
        let pathID = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { try await gate.load() }
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
        }

        await store.send(.connectionEvent(.authenticated(studio.id))) {
            $0.connectedMacIDs = [studio.id]
            $0.metadataRefreshGeneration = 1
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.connectionStatuses[studio.id] = .connected
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await gate.waitUntilEntered()
        let intent = RemoteAppPersistenceIntent(
            writerID: store.state.persistenceWriterID,
            sequence: 1,
            selectedMacID: laptop.id,
            hasCompletedInitialSetup: true
        )
        await store.send(.path(.element(id: pathID, action: .settings(.delegate(.paired(laptop)))))) {
            $0.pairedMacs = [studio, laptop]
            $0.selectedMacID = laptop.id
            $0.connectedMacIDs = [laptop.id]
            $0.metadataRefreshGeneration = 2
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.pairedMacs = [studio, laptop]
                settings.selectedMacID = laptop.id
                settings.connectionStatuses = [laptop.id: .connected]
                $0.path[id: pathID] = .settings(settings)
            }
            $0.nextPersistenceSequence = 1
            $0.pendingPersistenceIntent = intent
            $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .success)) {
            $0.pendingPersistenceIntent = nil
            $0.isPersisting = false
        }
        await gate.open()
        await store.send(.pairedMetadataRefreshed(1, [studio]))
        await store.finish()
        #expect(store.state.pairedMacs == [studio, laptop])
    }

    @Test func staleMetadataRefreshCannotResurrectForgottenMacInSettings() async throws {
        let gate = MetadataLoadGate(result: [studio, laptop])
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio, laptop]
        state.selectedMacID = laptop.id
        state.path.append(.settings(.init(isSetupRequired: false, pairedMacs: [studio, laptop], selectedMacID: laptop.id)))
        let pathID = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { try await gate.load() }
        }

        await store.send(.connectionEvent(.authenticated(laptop.id))) {
            $0.connectedMacIDs = [laptop.id]
            $0.metadataRefreshGeneration = 1
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.connectionStatuses[laptop.id] = .connected
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await gate.waitUntilEntered()
        await store.send(.path(.element(id: pathID, action: .settings(.delegate(.macForgotten(studio.id)))))) {
            $0.pairedMacs = [laptop]
            $0.metadataRefreshGeneration = 2
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.pairedMacs = [laptop]
                settings.connectionStatuses = [laptop.id: .connected]
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await gate.open()
        await store.send(.pairedMetadataRefreshed(1, [studio, laptop]))
        await store.finish()
        #expect(store.state.pairedMacs == [laptop])
    }

    @Test func authoritativeMetadataMembershipChangeReconcilesSelectionAndInvalidatesGeneration() async throws {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio, laptop]
        state.selectedMacID = studio.id
        state.connectedMacIDs = [studio.id]
        state.metadataRefreshGeneration = 4
        state.path.append(.settings(.init(
            isSetupRequired: false,
            pairedMacs: [studio, laptop],
            selectedMacID: studio.id,
            connectionStatuses: [studio.id: .connected]
        )))
        let pathID = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) { RemoteAppFeature() }

        await store.send(.pairedMetadataRefreshed(4, [laptop])) {
            $0.pairedMacs = [laptop]
            $0.selectedMacID = laptop.id
            $0.connectedMacIDs = []
            $0.metadataRefreshGeneration = 5
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.pairedMacs = [laptop]
                settings.selectedMacID = laptop.id
                settings.connectionStatuses = [:]
                $0.path[id: pathID] = .settings(settings)
            }
        }
    }

    @Test func invalidPersistedSelectionFallsBackAndPersists() async {
        let persistence = PersistenceAttemptRecorder(shouldFail: false); let selected = SelectionRecorder(); let studio = studio
        let store = TestStore(initialState: RemoteAppFeature.State(hasCompletedInitialSetup: true)) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [studio] }
            $0.remotePersistence.loadSelectedMacID = { UUID() }
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { await selected.record($0) }
        }
        await store.send(.task) { $0.loadGeneration = 1; $0.isLoading = true }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: studio.id, hasCompletedInitialSetup: true)
        await store.receive(\.launchResponse) {
            $0.isLoading = false; $0.pairedMacs = [studio]; $0.selectedMacID = studio.id
            $0.nextPersistenceSequence = 1; $0.pendingPersistenceIntent = intent; $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .success)) { $0.pendingPersistenceIntent = nil; $0.isPersisting = false }
        await store.finish()
        #expect(await persistence.selectedIDs == [studio.id]); #expect(await persistence.completionValues == [true]); #expect(await selected.ids == [studio.id])
    }

    @Test func hamburgerPushesNormalSettings() async {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true); state.pairedMacs = [studio]; state.selectedMacID = studio.id
        let store = TestStore(initialState: state) { RemoteAppFeature() }
        await store.send(.settingsButtonTapped) { $0.path.append(.settings(.init(isSetupRequired: false, pairedMacs: [studio], selectedMacID: studio.id))) }
    }

    @Test func settingsMacSelectionAtomicallyPersistsAndSelectsConnection() async throws {
        let persistence = PersistenceAttemptRecorder(shouldFail: false)
        let selections = SelectionRecorder()
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio, laptop]
        state.selectedMacID = studio.id
        state.path.append(.settings(.init(isSetupRequired: false, pairedMacs: [studio, laptop], selectedMacID: studio.id)))
        let pathID = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { await selections.record($0) }
        }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: laptop.id, hasCompletedInitialSetup: true)

        await store.send(.path(.element(id: pathID, action: .settings(.delegate(.selectedMacChanged(laptop)))))) {
            $0.selectedMacID = laptop.id
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.selectedMacID = laptop.id
                $0.path[id: pathID] = .settings(settings)
            }
            $0.nextPersistenceSequence = 1; $0.pendingPersistenceIntent = intent; $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .success)) { $0.pendingPersistenceIntent = nil; $0.isPersisting = false }
        await store.finish()
        #expect(await selections.ids == [laptop.id])
        #expect(await persistence.selectedIDs == [laptop.id])
    }

    @Test func forgettingNonselectedMacUpdatesRootCollection() async throws {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio, laptop]
        state.selectedMacID = studio.id
        state.path.append(.settings(.init(isSetupRequired: false, pairedMacs: [studio, laptop], selectedMacID: studio.id)))
        let pathID = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) { RemoteAppFeature() }

        await store.send(.path(.element(id: pathID, action: .settings(.delegate(.macForgotten(laptop.id)))))) {
            $0.pairedMacs = [studio]
            $0.metadataRefreshGeneration = 1
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.pairedMacs = [studio]
                $0.path[id: pathID] = .settings(settings)
            }
        }
    }

    @Test func attemptedNormalNavigationCannotReplaceRequiredSettingsOrPairingState() async {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: false)
        state.requiredSettings?.pairing = PairingFeature.State(code: "ABCDEFGHJKMN")
        let original = state.requiredSettings
        let store = TestStore(initialState: state) { RemoteAppFeature() }
        await store.send(.settingsButtonTapped)
        #expect(store.state.requiredSettings == original)
        #expect(store.state.path.isEmpty)
    }

    @Test func requiredPairingSuccessRevealsDashboardAndPersistsCompletion() async {
        let persistence = PersistenceAttemptRecorder(shouldFail: false); let selected = SelectionRecorder(); let studio = studio
        let store = TestStore(initialState: RemoteAppFeature.State(hasCompletedInitialSetup: false)) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { await selected.record($0) }
        }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: studio.id, hasCompletedInitialSetup: true)
        await store.send(.requiredSettings(.delegate(.paired(studio)))) {
            $0.requiredSettings = nil; $0.hasCompletedInitialSetup = true; $0.pairedMacs = [studio]; $0.selectedMacID = studio.id
            $0.connectedMacIDs = [studio.id]; $0.metadataRefreshGeneration = 1
            $0.nextPersistenceSequence = 1; $0.pendingPersistenceIntent = intent; $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .success)) { $0.pendingPersistenceIntent = nil; $0.isPersisting = false }
        await store.finish()
        #expect(await persistence.selectedIDs == [studio.id]); #expect(await persistence.completionValues == [true]); #expect(await selected.ids.isEmpty)
    }

    @Test func removingFinalMacCreatesRequiredChild() async throws {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true); state.pairedMacs = [studio]; state.selectedMacID = studio.id
        state.path.append(.settings(.init(isSetupRequired: false, pairedMacs: [studio], selectedMacID: studio.id)))
        let id = try #require(state.path.ids.last); let selected = SelectionRecorder(); let persistence = PersistenceAttemptRecorder(shouldFail: false)
        let store = TestStore(initialState: state) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { await selected.record($0) }
        }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: nil, hasCompletedInitialSetup: false)
        await store.send(.path(.element(id: id, action: .settings(.delegate(.allMacsRemoved))))) {
            $0.pairedMacs = []; $0.selectedMacID = nil; $0.path.removeAll(); $0.requiredSettings = .init(isSetupRequired: true)
            $0.metadataRefreshGeneration = 1; $0.hasCompletedInitialSetup = false
            $0.nextPersistenceSequence = 1; $0.pendingPersistenceIntent = intent; $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .success)) { $0.pendingPersistenceIntent = nil; $0.isPersisting = false }
        await store.finish(); #expect(await selected.ids == [nil]); #expect(await persistence.completionValues == [false])
    }

    @Test func completedLaunchWithNoMacsShowsRequiredSettings() async {
        let persistence = PersistenceAttemptRecorder(shouldFail: false)
        let store = TestStore(initialState: RemoteAppFeature.State(hasCompletedInitialSetup: true)) { RemoteAppFeature() } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [] }; $0.remotePersistence.loadSelectedMacID = { nil }
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { _ in }
        }
        await store.send(.task) { $0.loadGeneration = 1; $0.isLoading = true }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: nil, hasCompletedInitialSetup: false)
        await store.receive(.launchResponse(1, .success(.init(pairedMacs: [], selectedMacID: nil)))) {
            $0.isLoading = false; $0.requiredSettings = .init(isSetupRequired: true); $0.hasCompletedInitialSetup = false
            $0.nextPersistenceSequence = 1; $0.pendingPersistenceIntent = intent; $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .success)) { $0.pendingPersistenceIntent = nil; $0.isPersisting = false }
        #expect(await persistence.completionValues == [false])
    }

    @Test func staleLaunchResponseIsIgnored() async {
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true); state.loadGeneration = 2; state.isLoading = true
        let store = TestStore(initialState: state) { RemoteAppFeature() }
        await store.send(.launchResponse(1, .success(.init(pairedMacs: [studio], selectedMacID: studio.id))))
    }

    @Test func sceneLifecycleForwardsLatestState() async {
        let recorder = ForegroundRecorder(); let store = TestStore(initialState: RemoteAppFeature.State(hasCompletedInitialSetup: true)) { RemoteAppFeature() } withDependencies: {
            $0.remoteConnection.setForegrounded = { await recorder.record($0) }
        }
        await store.send(.scenePhaseChanged(false)) { $0.isForegrounded = false; $0.lifecycleGeneration = 1 }; await store.receive(.lifecycleResponse(1))
        await store.send(.scenePhaseChanged(true)) { $0.isForegrounded = true; $0.lifecycleGeneration = 2 }; await store.receive(.lifecycleResponse(2))
        #expect(await recorder.values == [false, true])
    }

    @Test func authoritativeEmptyStorageRepairsCompletedSeedAndRequiresSetup() async {
        let persistence = PersistenceAttemptRecorder(shouldFail: false)
        let selected = SelectionRecorder()
        let studio = studio
        let store = TestStore(
            initialState: RemoteAppFeature.State(hasCompletedInitialSetup: true)
        ) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [] }
            $0.remotePersistence.loadSelectedMacID = { studio.id }
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { await selected.record($0) }
        }

        await store.send(.task) {
            $0.loadGeneration = 1
            $0.isLoading = true
        }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: nil, hasCompletedInitialSetup: false)
        await store.receive(.launchResponse(1, .success(.init(pairedMacs: [], selectedMacID: studio.id)))) {
            $0.isLoading = false
            $0.requiredSettings = .init(isSetupRequired: true)
            $0.hasCompletedInitialSetup = false
            $0.nextPersistenceSequence = 1
            $0.pendingPersistenceIntent = intent
            $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .success)) {
            $0.pendingPersistenceIntent = nil
            $0.isPersisting = false
        }
        await store.finish()

        #expect(await persistence.selectedIDs == [nil])
        #expect(await persistence.completionValues == [false])
        #expect(await selected.ids == [nil])
    }

    @Test func authoritativeNonemptyStorageRepairsIncompleteSeedAndRevealsDashboard() async {
        let persistence = PersistenceAttemptRecorder(shouldFail: false)
        let selected = SelectionRecorder()
        let studio = studio
        let store = TestStore(
            initialState: RemoteAppFeature.State(hasCompletedInitialSetup: false)
        ) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { [studio] }
            $0.remotePersistence.loadSelectedMacID = { studio.id }
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { await selected.record($0) }
        }

        await store.send(.task) {
            $0.loadGeneration = 1
            $0.isLoading = true
        }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: studio.id, hasCompletedInitialSetup: true)
        await store.receive(.launchResponse(1, .success(.init(pairedMacs: [studio], selectedMacID: studio.id)))) {
            $0.isLoading = false
            $0.pairedMacs = [studio]
            $0.selectedMacID = studio.id
            $0.requiredSettings = nil
            $0.hasCompletedInitialSetup = true
            $0.nextPersistenceSequence = 1
            $0.pendingPersistenceIntent = intent
            $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .success)) {
            $0.pendingPersistenceIntent = nil
            $0.isPersisting = false
        }
        await store.finish()

        #expect(await persistence.selectedIDs == [studio.id])
        #expect(await persistence.completionValues == [true])
        #expect(await selected.ids == [studio.id])
    }

    @Test func launchLoadFailurePreservesSeededRootStateAndCanRetry() async throws {
        let loader = RetryableLaunchLoader(macs: [studio], selectedMacID: studio.id)
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [laptop]
        state.selectedMacID = laptop.id
        state.path.append(.settings(.init(isSetupRequired: false, pairedMacs: [laptop], selectedMacID: laptop.id)))
        let originalPath = state.path
        let store = TestStore(initialState: state) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.loadPairedMacs = { try await loader.loadMacs() }
            $0.remotePersistence.loadSelectedMacID = { await loader.selectedMacID }
            $0.remoteConnection.select = { _ in }
        }

        await store.send(.task) {
            $0.loadGeneration = 1
            $0.isLoading = true
        }
        await store.receive(.launchResponse(1, .failure)) {
            $0.isLoading = false
            $0.rootIssue = .loadFailed
        }
        #expect(store.state.pairedMacs == [laptop])
        #expect(store.state.selectedMacID == laptop.id)
        #expect(store.state.path == originalPath)

        await loader.allowSuccess()
        await store.send(.retryTapped)
        await store.receive(.task) {
            $0.loadGeneration = 2
            $0.isLoading = true
        }
        await store.receive(.launchResponse(2, .success(.init(pairedMacs: [studio], selectedMacID: studio.id)))) {
            $0.isLoading = false
            $0.rootIssue = nil
            $0.pairedMacs = [studio]
            $0.selectedMacID = studio.id
            if let pathID = $0.path.ids.last,
               case var .settings(settings) = $0.path[id: pathID] {
                settings.pairedMacs = [studio]
                settings.selectedMacID = studio.id
                $0.path[id: pathID] = .settings(settings)
            }
        }
        await store.finish()
    }

    @Test func pairingPersistenceFailureRetainsIntentAndRetrySuccessClearsIt() async {
        let persistence = PersistenceAttemptRecorder(shouldFail: true)
        let studio = studio
        let store = TestStore(
            initialState: RemoteAppFeature.State(hasCompletedInitialSetup: false)
        ) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { _ in }
        }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: studio.id, hasCompletedInitialSetup: true)

        await store.send(.requiredSettings(.delegate(.paired(studio)))) {
            $0.requiredSettings = nil
            $0.hasCompletedInitialSetup = true
            $0.pairedMacs = [studio]
            $0.selectedMacID = studio.id
            $0.connectedMacIDs = [studio.id]
            $0.metadataRefreshGeneration = 1
            $0.nextPersistenceSequence = 1
            $0.pendingPersistenceIntent = intent
            $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .failure)) {
            $0.isPersisting = false
            $0.rootIssue = .persistenceFailed
        }

        await persistence.allowSuccess()
        await store.send(.retryTapped) { $0.isPersisting = true }
        await store.receive(.persistenceResponse(intent, .success)) {
            $0.pendingPersistenceIntent = nil
            $0.isPersisting = false
            $0.rootIssue = nil
        }
        await store.finish()
    }

    @Test func finalRemovalPersistenceFailureRetainsIntentAndRetrySuccessClearsIt() async throws {
        let persistence = PersistenceAttemptRecorder(shouldFail: true)
        var state = RemoteAppFeature.State(hasCompletedInitialSetup: true)
        state.pairedMacs = [studio]
        state.selectedMacID = studio.id
        state.path.append(.settings(.init(isSetupRequired: false, pairedMacs: [studio], selectedMacID: studio.id)))
        let id = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.saveAppState = { try await persistence.save($0) }
            $0.remoteConnection.select = { _ in }
        }
        let intent = RemoteAppPersistenceIntent(writerID: store.state.persistenceWriterID, sequence: 1, selectedMacID: nil, hasCompletedInitialSetup: false)

        await store.send(.path(.element(id: id, action: .settings(.delegate(.allMacsRemoved))))) {
            $0.pairedMacs = []
            $0.selectedMacID = nil
            $0.path.removeAll()
            $0.requiredSettings = .init(isSetupRequired: true)
            $0.metadataRefreshGeneration = 1
            $0.hasCompletedInitialSetup = false
            $0.nextPersistenceSequence = 1
            $0.pendingPersistenceIntent = intent
            $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(intent, .failure)) {
            $0.isPersisting = false
            $0.rootIssue = .persistenceFailed
        }

        await persistence.allowSuccess()
        await store.send(.retryTapped) { $0.isPersisting = true }
        await store.receive(.persistenceResponse(intent, .success)) {
            $0.pendingPersistenceIntent = nil
            $0.isPersisting = false
            $0.rootIssue = nil
        }
        await store.finish()
    }

    @Test func rapidPairThenFinalRemovalKeepsNewestStorageWhenOlderSaveCompletesLast() async throws {
        let backing = RemotePersistenceClient.inMemory()
        let saver = ReverseAtomicAppStateSaver(backing: backing)
        let writerID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        var state = RemoteAppFeature.State(
            hasCompletedInitialSetup: true,
            persistenceWriterID: writerID
        )
        state.pairedMacs = [studio]
        state.selectedMacID = studio.id
        state.path.append(.settings(.init(
            isSetupRequired: false,
            pairedMacs: [studio],
            selectedMacID: studio.id
        )))
        let pathID = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.saveAppState = { try await saver.save($0) }
            $0.remoteConnection.select = { _ in }
        }
        let pairedIntent = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 1,
            selectedMacID: laptop.id,
            hasCompletedInitialSetup: true
        )
        let clearedIntent = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 2,
            selectedMacID: nil,
            hasCompletedInitialSetup: false
        )

        await store.send(.path(.element(id: pathID, action: .settings(.delegate(.paired(laptop)))))) {
            $0.pairedMacs = [self.studio, self.laptop]
            $0.selectedMacID = self.laptop.id
            $0.connectedMacIDs = [self.laptop.id]
            $0.metadataRefreshGeneration = 1
            if case var .settings(settings) = $0.path[id: pathID] {
                settings.pairedMacs = [self.studio, self.laptop]
                settings.selectedMacID = self.laptop.id
                settings.connectionStatuses = [self.laptop.id: .connected]
                $0.path[id: pathID] = .settings(settings)
            }
            $0.nextPersistenceSequence = 1
            $0.pendingPersistenceIntent = pairedIntent
            $0.isPersisting = true
        }
        await saver.waitUntilFirstSaveStarts()
        await store.send(.path(.element(id: pathID, action: .settings(.delegate(.allMacsRemoved))))) {
            $0.pairedMacs = []
            $0.selectedMacID = nil
            $0.path.removeAll()
            $0.requiredSettings = .init(isSetupRequired: true)
            $0.connectedMacIDs = []
            $0.metadataRefreshGeneration = 2
            $0.hasCompletedInitialSetup = false
            $0.nextPersistenceSequence = 2
            $0.pendingPersistenceIntent = clearedIntent
            $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(clearedIntent, .success)) {
            $0.pendingPersistenceIntent = nil
            $0.isPersisting = false
        }
        await saver.releaseFirstSave()
        await store.receive(.persistenceResponse(pairedIntent, .success))
        await store.finish()

        #expect(try await backing.loadSelectedMacID() == nil)
        #expect(try await backing.loadInitialSetupCompleted() == false)
    }

    @Test func rapidFinalRemovalThenPairKeepsNewestStorageWhenOlderSaveCompletesLast() async throws {
        let backing = RemotePersistenceClient.inMemory()
        let saver = ReverseAtomicAppStateSaver(backing: backing)
        let writerID = UUID(uuidString: "00000000-0000-0000-0000-000000000902")!
        var state = RemoteAppFeature.State(
            hasCompletedInitialSetup: true,
            persistenceWriterID: writerID
        )
        state.pairedMacs = [studio]
        state.selectedMacID = studio.id
        state.path.append(.settings(.init(
            isSetupRequired: false,
            pairedMacs: [studio],
            selectedMacID: studio.id
        )))
        let pathID = try #require(state.path.ids.last)
        let store = TestStore(initialState: state) {
            RemoteAppFeature()
        } withDependencies: {
            $0.remotePersistence.saveAppState = { try await saver.save($0) }
            $0.remoteConnection.select = { _ in }
        }
        let clearedIntent = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 1,
            selectedMacID: nil,
            hasCompletedInitialSetup: false
        )
        let pairedIntent = RemoteAppPersistenceIntent(
            writerID: writerID,
            sequence: 2,
            selectedMacID: laptop.id,
            hasCompletedInitialSetup: true
        )

        await store.send(.path(.element(id: pathID, action: .settings(.delegate(.allMacsRemoved))))) {
            $0.pairedMacs = []
            $0.selectedMacID = nil
            $0.path.removeAll()
            $0.requiredSettings = .init(isSetupRequired: true)
            $0.metadataRefreshGeneration = 1
            $0.hasCompletedInitialSetup = false
            $0.nextPersistenceSequence = 1
            $0.pendingPersistenceIntent = clearedIntent
            $0.isPersisting = true
        }
        await saver.waitUntilFirstSaveStarts()
        await store.send(.requiredSettings(.delegate(.paired(laptop)))) {
            $0.requiredSettings = nil
            $0.hasCompletedInitialSetup = true
            $0.pairedMacs = [laptop]
            $0.selectedMacID = laptop.id
            $0.connectedMacIDs = [laptop.id]
            $0.metadataRefreshGeneration = 2
            $0.nextPersistenceSequence = 2
            $0.pendingPersistenceIntent = pairedIntent
            $0.isPersisting = true
        }
        await store.receive(.persistenceResponse(pairedIntent, .success)) {
            $0.pendingPersistenceIntent = nil
            $0.isPersisting = false
        }
        await saver.releaseFirstSave()
        await store.receive(.persistenceResponse(clearedIntent, .success))
        await store.finish()

        #expect(try await backing.loadSelectedMacID() == laptop.id)
        #expect(try await backing.loadInitialSetupCompleted())
    }
}

private actor SelectionRecorder { private(set) var ids: [UUID?] = []; func record(_ mac: PairedMac?) { ids.append(mac?.id) }; func recordID(_ id: UUID?) { ids.append(id) } }
private actor ForegroundRecorder { private(set) var values: [Bool] = []; func record(_ value: Bool) { values.append(value) } }

private actor MetadataLoadGate {
    private let result: [PairedMac]
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var openContinuation: CheckedContinuation<Void, Never>?

    init(result: [PairedMac]) { self.result = result }

    func load() async throws -> [PairedMac] {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { openContinuation = $0 }
        return result
    }

    func waitUntilEntered() async {
        guard entered == false else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        openContinuation?.resume()
        openContinuation = nil
    }
}

private enum TestPersistenceError: Error { case failed }

private actor PersistenceAttemptRecorder {
    private var shouldFail: Bool
    private(set) var selectedIDs: [UUID?] = []
    private(set) var completionValues: [Bool] = []

    init(shouldFail: Bool) { self.shouldFail = shouldFail }

    func save(_ intent: RemoteAppPersistenceIntent) throws {
        selectedIDs.append(intent.selectedMacID)
        completionValues.append(intent.hasCompletedInitialSetup)
        if shouldFail { throw TestPersistenceError.failed }
    }

    func allowSuccess() { shouldFail = false }
}

private actor RetryableLaunchLoader {
    let macs: [PairedMac]
    let selectedMacID: UUID?
    private var shouldFail = true

    init(macs: [PairedMac], selectedMacID: UUID?) {
        self.macs = macs
        self.selectedMacID = selectedMacID
    }

    func loadMacs() throws -> [PairedMac] {
        if shouldFail { throw TestPersistenceError.failed }
        return macs
    }

    func allowSuccess() { shouldFail = false }
}

private actor ReverseAtomicAppStateSaver {
    private let backing: RemotePersistenceClient
    private var callCount = 0
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?
    private var firstStartWaiters: [CheckedContinuation<Void, Never>] = []

    init(backing: RemotePersistenceClient) {
        self.backing = backing
    }

    func save(_ intent: RemoteAppPersistenceIntent) async throws {
        callCount += 1
        if callCount == 1 {
            let waiters = firstStartWaiters
            firstStartWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { firstSaveContinuation = $0 }
        }
        try await backing.saveAppState(intent)
    }

    func waitUntilFirstSaveStarts() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { firstStartWaiters.append($0) }
    }

    func releaseFirstSave() {
        firstSaveContinuation?.resume()
        firstSaveContinuation = nil
    }
}
