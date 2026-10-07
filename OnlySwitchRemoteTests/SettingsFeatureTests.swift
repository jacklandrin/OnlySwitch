import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct SettingsFeatureTests {
    private let studio = PairedMac(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
        displayName: "Studio",
        lastEndpointDescription: "studio.local",
        lastConnectedAt: nil,
        requiresPairing: false
    )
    private let laptop = PairedMac(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!,
        displayName: "Laptop",
        lastEndpointDescription: nil,
        lastConnectedAt: nil,
        requiresPairing: false
    )
    private let mute = RemoteControlID(kind: .builtIn, value: "mute")
    private let shortcut = RemoteControlID(kind: .shortcut, value: "Lights")
    private let evolution = RemoteControlID(kind: .evolution, value: "evolution-id")
    private let missing = RemoteControlID(kind: .builtIn, value: "missing")

    @Test func switchingMacLoadsOnlyItsOwnLayoutAndCatalog() async {
        let laptop = laptop
        let mute = mute
        let cache = RemoteCatalogCache(revision: 7, controls: [descriptor(mute)])
        let layout = MacDashboardLayout(macID: laptop.id, selectedControlIDs: [mute], order: [mute])
        let store = TestStore(initialState: SettingsFeature.State(
            pairedMacs: [studio, laptop],
            selectedMacID: studio.id
        )) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.loadLayout = { id in id == laptop.id ? layout : nil }
            $0.remotePersistence.loadCatalog = { id in id == laptop.id ? cache : nil }
        }

        await store.send(.selectedMacChanged(laptop.id)) {
            $0.selectedMacID = laptop.id
            $0.selectionGeneration = 1
            $0.catalog = []
            $0.catalogRevision = 0
            $0.selectedControlIDs = []
            $0.order = []
        }
        await store.receive(.delegate(.selectedMacChanged(laptop)))
        await store.receive(.selectedMacDataLoaded(1, laptop.id, layout, cache)) {
            $0.catalog = [descriptor(mute)]
            $0.catalogRevision = 7
            $0.selectedControlIDs = [mute]
            $0.order = [mute]
        }
        await store.finish()
    }

    @Test func staleSwitchLoadAndOtherMacCatalogEventsAreIgnored() async {
        var state = SettingsFeature.State(pairedMacs: [studio, laptop], selectedMacID: laptop.id)
        state.selectionGeneration = 2
        let store = TestStore(initialState: state) { SettingsFeature() }
        let staleLayout = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute], order: [mute])

        await store.send(.selectedMacDataLoaded(1, studio.id, staleLayout, nil))
        await store.send(.connectionEvent(.catalog(studio.id, 9, [descriptor(shortcut)])))
        #expect(store.state.selectedControlIDs.isEmpty)
        #expect(store.state.catalog.isEmpty)
    }

    @Test func switchingBackKeepsNewestUnsavedLayoutForRetry() async {
        var state = SettingsFeature.State(pairedMacs: [studio, laptop], selectedMacID: studio.id)
        state.selectionGeneration = 3
        let pending = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [shortcut, mute])
        state.pendingLayoutSaves[studio.id] = pending
        state.layoutSaveIssueMacIDs.insert(studio.id)
        let staleDisk = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute], order: [mute])
        let store = TestStore(initialState: state) { SettingsFeature() }

        await store.send(.selectedMacDataLoaded(3, studio.id, staleDisk, nil)) {
            $0.selectedControlIDs = [mute, shortcut]
            $0.order = [shortcut, mute]
        }
    }

    @Test func unavailableControlCanRemainSelectedAndShowsReason() async {
        let unavailable = descriptor(mute, available: false, reason: "Configure audio on the Mac")
        let store = TestStore(initialState: SettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            catalog: [unavailable]
        )) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.saveLayout = { _ in }
        }

        await store.send(.toggleControl(unavailable.id, true)) {
            $0.selectedControlIDs = [unavailable.id]
            $0.order = [unavailable.id]
            $0.pendingLayoutSaves[studio.id] = MacDashboardLayout(
                macID: studio.id,
                selectedControlIDs: [unavailable.id],
                order: [unavailable.id]
            )
            $0.layoutSaveGenerations[studio.id] = 1
            $0.layoutSaveInFlight.insert(studio.id)
        }
        let layout = MacDashboardLayout(macID: studio.id, selectedControlIDs: [unavailable.id], order: [unavailable.id])
        await store.receive(.delegate(.layoutChanged(layout)))
        await store.receive(.layoutSaveResponse(studio.id, 1, layout, .success)) {
            $0.pendingLayoutSaves[studio.id] = nil
            $0.layoutSaveInFlight.remove(studio.id)
        }
        #expect(store.state.catalog[id: unavailable.id]?.unavailableReason == "Configure audio on the Mac")
    }

    @Test func groupedControlsIncludeAllKindsAndMissingIDsAreNotRendered() {
        let state = SettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            catalog: [descriptor(mute), descriptor(shortcut), descriptor(evolution)],
            selectedControlIDs: [mute, shortcut, evolution, missing],
            order: [missing, evolution, mute, shortcut]
        )

        #expect(state.controls(kind: .builtIn).map(\.id) == [mute])
        #expect(state.controls(kind: .shortcut).map(\.id) == [shortcut])
        #expect(state.controls(kind: .evolution).map(\.id) == [evolution])
        #expect(state.orderedVisibleSelectedControlIDs == [evolution, mute, shortcut])
        #expect(state.order == [missing, evolution, mute, shortcut])
    }

    @Test func availableControlsExcludeItemsAlreadyOnTheDashboard() {
        let state = SettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            catalog: [descriptor(mute), descriptor(shortcut), descriptor(evolution)],
            selectedControlIDs: [mute, evolution],
            order: [mute, evolution]
        )

        #expect(state.availableControls(kind: .builtIn).map(\.id).isEmpty)
        #expect(state.availableControls(kind: .shortcut).map(\.id) == [shortcut])
        #expect(state.availableControls(kind: .evolution).map(\.id).isEmpty)
    }

    @Test func onlyBuiltInControlsUseCatalogLocalizationKeys() {
        let builtIn = descriptor(mute)
        let userShortcut = descriptor(shortcut)
        let evolutionReason = "This Evolution is missing its command"
        let unavailableEvolution = descriptor(evolution, available: false, reason: evolutionReason)

        #expect(builtIn.titleLocalizationKey == mute.value)
        #expect(userShortcut.titleLocalizationKey == nil)
        #expect(unavailableEvolution.titleLocalizationKey == nil)
        #expect(unavailableEvolution.unavailableReasonLocalizationKey == evolutionReason)
    }

    @Test func selectedControlsMissingFromSavedOrderRemainVisibleForRemoval() {
        let state = SettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            catalog: [descriptor(mute), descriptor(shortcut)],
            selectedControlIDs: [mute, shortcut],
            order: [mute]
        )

        #expect(state.orderedVisibleSelectedControlIDs == [mute, shortcut])
    }

    @Test func movingSelectedControlMissingFromSavedOrderPersistsItsNewPosition() async {
        let store = TestStore(initialState: SettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            catalog: [descriptor(mute), descriptor(shortcut)],
            selectedControlIDs: [mute, shortcut],
            order: [mute]
        )) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.saveLayout = { _ in }
        }

        await store.send(.move(IndexSet(integer: 1), 0)) {
            $0.order = [shortcut, mute]
            $0.pendingLayoutSaves[studio.id] = .init(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [shortcut, mute])
            $0.layoutSaveGenerations[studio.id] = 1
            $0.layoutSaveInFlight.insert(studio.id)
        }
        let layout = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [shortcut, mute])
        await store.receive(.delegate(.layoutChanged(layout)))
        await store.receive(.layoutSaveResponse(studio.id, 1, layout, .success)) {
            $0.pendingLayoutSaves[studio.id] = nil
            $0.layoutSaveInFlight.remove(studio.id)
        }
    }

    @Test func movingFilteredSelectedRowsProjectsBackWithoutDroppingMissingIDs() async {
        let recorder = LayoutSaveRecorder()
        let store = TestStore(initialState: SettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            catalog: [descriptor(mute), descriptor(shortcut), descriptor(evolution)],
            selectedControlIDs: [missing, mute, shortcut, evolution],
            order: [missing, mute, shortcut, evolution]
        )) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.saveLayout = { try await recorder.save($0) }
        }

        await store.send(.move(IndexSet(integer: 0), 3)) {
            $0.order = [missing, shortcut, evolution, mute]
            let layout = MacDashboardLayout(macID: studio.id, selectedControlIDs: [missing, mute, shortcut, evolution], order: [missing, shortcut, evolution, mute])
            $0.pendingLayoutSaves[studio.id] = layout
            $0.layoutSaveGenerations[studio.id] = 1
            $0.layoutSaveInFlight.insert(studio.id)
        }
        let saved = MacDashboardLayout(macID: studio.id, selectedControlIDs: [missing, mute, shortcut, evolution], order: [missing, shortcut, evolution, mute])
        await store.receive(.delegate(.layoutChanged(saved)))
        await store.receive(.layoutSaveResponse(studio.id, 1, saved, .success)) {
            $0.pendingLayoutSaves[studio.id] = nil
            $0.layoutSaveInFlight.remove(studio.id)
        }
        #expect(await recorder.layouts.last?.order == [missing, shortcut, evolution, mute])
    }

    @Test func failedLayoutSaveIsRetriedWithNewestMonotonicLayout() async {
        let recorder = GatedLayoutSaveRecorder()
        let store = TestStore(initialState: SettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            catalog: [descriptor(mute), descriptor(shortcut)]
        )) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.saveLayout = { try await recorder.save($0) }
        }

        await store.send(.toggleControl(mute, true)) {
            $0.selectedControlIDs = [mute]; $0.order = [mute]
            $0.pendingLayoutSaves[studio.id] = .init(macID: studio.id, selectedControlIDs: [mute], order: [mute])
            $0.layoutSaveGenerations[studio.id] = 1; $0.layoutSaveInFlight.insert(studio.id)
        }
        await store.receive(.delegate(.layoutChanged(.init(macID: studio.id, selectedControlIDs: [mute], order: [mute]))))
        await recorder.waitUntilFirstSaveStarts()
        await store.send(.toggleControl(shortcut, true)) {
            $0.selectedControlIDs = [mute, shortcut]; $0.order = [mute, shortcut]
            $0.pendingLayoutSaves[studio.id] = .init(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [mute, shortcut])
        }
        await store.receive(.delegate(.layoutChanged(.init(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [mute, shortcut]))))
        await recorder.failFirstSave()
        let first = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute], order: [mute])
        await store.receive(.layoutSaveResponse(studio.id, 1, first, .failure)) {
            $0.layoutSaveInFlight.remove(studio.id); $0.layoutSaveIssueMacIDs.insert(studio.id)
        }
        await store.send(.retryLayoutSave(studio.id)) {
            $0.layoutSaveGenerations[studio.id] = 2; $0.layoutSaveInFlight.insert(studio.id)
        }
        let latest = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [mute, shortcut])
        await store.receive(.layoutSaveResponse(studio.id, 2, latest, .success)) {
            $0.pendingLayoutSaves[studio.id] = nil; $0.layoutSaveInFlight.remove(studio.id); $0.layoutSaveIssueMacIDs.remove(studio.id)
        }
        #expect(await recorder.layouts.map(\.order) == [[mute], [mute, shortcut]])
    }

    @Test func successfulOldSaveCannotOverwriteNewerRapidToggle() async {
        let recorder = SuccessfulGatedLayoutSaveRecorder()
        let store = TestStore(initialState: SettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            catalog: [descriptor(mute), descriptor(shortcut)]
        )) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.saveLayout = { await recorder.save($0) }
        }

        await store.send(.toggleControl(mute, true)) {
            $0.selectedControlIDs = [mute]; $0.order = [mute]
            $0.pendingLayoutSaves[studio.id] = .init(macID: studio.id, selectedControlIDs: [mute], order: [mute])
            $0.layoutSaveGenerations[studio.id] = 1; $0.layoutSaveInFlight.insert(studio.id)
        }
        await store.receive(.delegate(.layoutChanged(.init(macID: studio.id, selectedControlIDs: [mute], order: [mute]))))
        await recorder.waitUntilFirstSaveStarts()
        await store.send(.toggleControl(shortcut, true)) {
            $0.selectedControlIDs = [mute, shortcut]; $0.order = [mute, shortcut]
            $0.pendingLayoutSaves[studio.id] = .init(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [mute, shortcut])
        }
        await store.receive(.delegate(.layoutChanged(.init(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [mute, shortcut]))))
        await recorder.finishFirstSave()
        let first = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute], order: [mute])
        await store.receive(.layoutSaveResponse(studio.id, 1, first, .success)) {
            $0.layoutSaveGenerations[studio.id] = 2
        }
        let latest = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [mute, shortcut])
        await store.receive(.layoutSaveResponse(studio.id, 2, latest, .success)) {
            $0.pendingLayoutSaves[studio.id] = nil; $0.layoutSaveInFlight.remove(studio.id)
        }
        #expect(await recorder.layouts.map(\.order) == [[mute], [mute, shortcut]])
    }

    @Test func catalogEventsUpdateCacheOnlyForSelectedMac() async {
        let cacheRecorder = CatalogSaveRecorder()
        var state = SettingsFeature.State(pairedMacs: [studio], selectedMacID: studio.id)
        state.isObservingConnectionEvents = true
        let controls = [descriptor(mute)]
        let store = TestStore(initialState: state) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.saveCatalog = { await cacheRecorder.save(macID: $0, revision: $1, controls: $2) }
        }

        await store.send(.connectionEvent(.catalog(studio.id, 12, controls))) {
            $0.catalog = IdentifiedArray(uniqueElements: controls); $0.catalogRevision = 12
        }
        await store.receive(.catalogCacheSaveResponse(studio.id, 12, .success))
        #expect(await cacheRecorder.revisions == [12])
    }

}

@MainActor
struct GlobalSettingsFeatureTests {
    private let studio = PairedMac(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000903")!,
        displayName: "Studio",
        lastEndpointDescription: nil,
        lastConnectedAt: nil,
        requiresPairing: false
    )
    private let laptop = PairedMac(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000904")!,
        displayName: "Laptop",
        lastEndpointDescription: "laptop.local",
        lastConnectedAt: nil,
        requiresPairing: false
    )

    @Test func pairNewMacPresentsTheGlobalPairingFlow() async {
        let store = TestStore(initialState: GlobalSettingsFeature.State()) {
            GlobalSettingsFeature()
        }

        await store.send(.pairNewMacTapped) {
            $0.pairing = PairingFeature.State()
        }
    }

    @Test func pairedMacIsDelegatedAndDismissesTheGlobalPairingFlow() async {
        var state = GlobalSettingsFeature.State()
        state.pairing = PairingFeature.State()
        let store = TestStore(initialState: state) {
            GlobalSettingsFeature()
        }

        await store.send(.pairing(.presented(.delegate(.paired(studio))))) {
            $0.pairing = nil
        }
        await store.receive(.delegate(.paired(studio)))
    }

    @Test func dismissalDoesNotInterruptPairingFinalization() async {
        var state = GlobalSettingsFeature.State()
        state.pairing = PairingFeature.State()
        state.pairing?.isFinalizing = true
        let store = TestStore(initialState: state) {
            GlobalSettingsFeature()
        }

        await store.send(.pairing(.dismiss))
        #expect(store.state.pairing?.isFinalizing == true)
    }

    @Test func foregroundChangesReachPresentedPairing() async {
        var state = GlobalSettingsFeature.State()
        state.pairing = PairingFeature.State()
        let store = TestStore(initialState: state) {
            GlobalSettingsFeature()
        }

        await store.send(.foregroundChanged(false))
        await store.receive(.pairing(.presented(.foregroundChanged(false)))) {
            $0.pairing?.isForegrounded = false
        }
    }

    @Test func keepingScreenAwakeIsPersisted() async {
        let recorder = IdleTimerRecorder()
        let store = TestStore(initialState: GlobalSettingsFeature.State()) {
            GlobalSettingsFeature()
        } withDependencies: {
            $0.remoteIdleTimer.savePreference = { await recorder.record($0) }
        }

        await store.send(.keepScreenAwakeToggled(true)) {
            $0.isKeepingScreenAwake = true
        }
        await store.finish()

        #expect(store.state.isKeepingScreenAwake == true)
        #expect(await recorder.values == [true])
    }

    @Test func pairedMacManagementIsPresentedFromGlobalSettings() async {
        let store = TestStore(initialState: GlobalSettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id,
            connectionStatuses: [studio.id: .connected]
        )) {
            GlobalSettingsFeature()
        }

        await store.send(.manageMac(studio.id)) {
            $0.management = .init(mac: studio, connectionStatus: .connected)
        }
    }

    @Test func selectingAMacFromGlobalSettingsDelegatesTheNewSelection() async {
        let store = TestStore(initialState: GlobalSettingsFeature.State(
            pairedMacs: [studio, laptop],
            selectedMacID: studio.id
        )) {
            GlobalSettingsFeature()
        }

        await store.send(.selectMac(laptop.id)) {
            $0.selectedMacID = laptop.id
        }
        await store.receive(.delegate(.selectedMacChanged(laptop)))
    }

    @Test func rePairFromGlobalSettingsKeepsTheMacAndStartsPairing() async {
        var state = GlobalSettingsFeature.State(
            pairedMacs: [studio, laptop],
            selectedMacID: studio.id
        )
        state.management = .init(mac: laptop)
        let store = TestStore(initialState: state) {
            GlobalSettingsFeature()
        }

        await store.send(.management(.presented(.delegate(.rePair(laptop.id))))) {
            $0.management = nil
            $0.pairing = PairingFeature.State()
        }
    }

    @Test func forgettingSelectedMacFromGlobalSettingsChoosesFallbackAndDelegatesSelection() async {
        var state = GlobalSettingsFeature.State(
            pairedMacs: [studio, laptop],
            selectedMacID: studio.id,
            connectionStatuses: [studio.id: .connected]
        )
        state.management = .init(mac: studio, connectionStatus: .connected)
        let store = TestStore(initialState: state) {
            GlobalSettingsFeature()
        }

        await store.send(.management(.presented(.delegate(.forgotten(studio.id))))) {
            $0.management = nil
            $0.pairedMacs = [laptop]
            $0.selectedMacID = laptop.id
            $0.connectionStatuses = [:]
        }
        await store.receive(.delegate(.macForgotten(studio.id)))
        await store.receive(.delegate(.selectedMacChanged(laptop)))
    }

    @Test func forgettingLastMacFromGlobalSettingsDelegatesSetupReset() async {
        var state = GlobalSettingsFeature.State(
            pairedMacs: [studio],
            selectedMacID: studio.id
        )
        state.management = .init(mac: studio)
        let store = TestStore(initialState: state) {
            GlobalSettingsFeature()
        }

        await store.send(.management(.presented(.delegate(.forgotten(studio.id))))) {
            $0.management = nil
            $0.pairedMacs = []
            $0.selectedMacID = nil
        }
        await store.receive(.delegate(.allMacsRemoved))
    }
}

extension SettingsFeatureTests {
    private func descriptor(_ id: RemoteControlID, available: Bool = true, reason: String? = nil) -> RemoteControlDescriptor {
        .init(
            id: id,
            title: id.value,
            behavior: .switch,
            icon: .systemSymbol("switch.2"),
            isAvailable: available,
            unavailableReason: reason,
            isDestructive: false,
            supportsStatus: true,
            supportsSecondaryInformation: true
        )
    }
}

private actor IdleTimerRecorder {
    private(set) var values: [Bool] = []

    func record(_ isDisabled: Bool) {
        values.append(isDisabled)
    }
}

private actor LayoutSaveRecorder {
    private(set) var layouts: [MacDashboardLayout] = []
    private var failFirst: Bool
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func save(_ layout: MacDashboardLayout) throws {
        layouts.append(layout)
        if failFirst { failFirst = false; throw SettingsTestError.failed }
    }
}

private actor CatalogSaveRecorder {
    private(set) var revisions: [UInt64] = []
    func save(macID: UUID, revision: UInt64, controls: [RemoteControlDescriptor]) {
        _ = macID; _ = controls; revisions.append(revision)
    }
}

private actor GatedLayoutSaveRecorder {
    private(set) var layouts: [MacDashboardLayout] = []
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private var firstStartedWaiter: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func save(_ layout: MacDashboardLayout) async throws {
        layouts.append(layout)
        guard layouts.count == 1 else { return }
        hasStarted = true
        firstStartedWaiter?.resume()
        firstStartedWaiter = nil
        await withCheckedContinuation { firstWaiter = $0 }
        throw SettingsTestError.failed
    }

    func waitUntilFirstSaveStarts() async {
        guard hasStarted == false else { return }
        await withCheckedContinuation { firstStartedWaiter = $0 }
    }

    func failFirstSave() {
        firstWaiter?.resume()
        firstWaiter = nil
    }
}

private actor SuccessfulGatedLayoutSaveRecorder {
    private(set) var layouts: [MacDashboardLayout] = []
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private var firstStartedWaiter: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func save(_ layout: MacDashboardLayout) async {
        layouts.append(layout)
        guard layouts.count == 1 else { return }
        hasStarted = true
        firstStartedWaiter?.resume()
        firstStartedWaiter = nil
        await withCheckedContinuation { firstWaiter = $0 }
    }

    func waitUntilFirstSaveStarts() async {
        guard hasStarted == false else { return }
        await withCheckedContinuation { firstStartedWaiter = $0 }
    }

    func finishFirstSave() {
        firstWaiter?.resume()
        firstWaiter = nil
    }
}

private enum SettingsTestError: Error { case failed }
