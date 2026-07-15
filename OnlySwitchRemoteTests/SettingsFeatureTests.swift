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
            isSetupRequired: false,
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
        var state = SettingsFeature.State(isSetupRequired: false, pairedMacs: [studio, laptop], selectedMacID: laptop.id)
        state.selectionGeneration = 2
        let store = TestStore(initialState: state) { SettingsFeature() }
        let staleLayout = MacDashboardLayout(macID: studio.id, selectedControlIDs: [mute], order: [mute])

        await store.send(.selectedMacDataLoaded(1, studio.id, staleLayout, nil))
        await store.send(.connectionEvent(.catalog(studio.id, 9, [descriptor(shortcut)])))
        #expect(store.state.selectedControlIDs.isEmpty)
        #expect(store.state.catalog.isEmpty)
    }

    @Test func switchingBackKeepsNewestUnsavedLayoutForRetry() async {
        var state = SettingsFeature.State(isSetupRequired: false, pairedMacs: [studio, laptop], selectedMacID: studio.id)
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
            isSetupRequired: false,
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
        await store.receive(.layoutSaveResponse(studio.id, 1, layout, .success)) {
            $0.pendingLayoutSaves[studio.id] = nil
            $0.layoutSaveInFlight.remove(studio.id)
        }
        #expect(store.state.catalog[id: unavailable.id]?.unavailableReason == "Configure audio on the Mac")
    }

    @Test func groupedControlsIncludeAllKindsAndMissingIDsAreNotRendered() {
        let state = SettingsFeature.State(
            isSetupRequired: false,
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

    @Test func movingFilteredSelectedRowsProjectsBackWithoutDroppingMissingIDs() async {
        let recorder = LayoutSaveRecorder()
        let store = TestStore(initialState: SettingsFeature.State(
            isSetupRequired: false,
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
        await store.receive(.layoutSaveResponse(studio.id, 1, saved, .success)) {
            $0.pendingLayoutSaves[studio.id] = nil
            $0.layoutSaveInFlight.remove(studio.id)
        }
        #expect(await recorder.layouts.last?.order == [missing, shortcut, evolution, mute])
    }

    @Test func failedLayoutSaveIsRetriedWithNewestMonotonicLayout() async {
        let recorder = GatedLayoutSaveRecorder()
        let store = TestStore(initialState: SettingsFeature.State(
            isSetupRequired: false,
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
        await recorder.waitUntilFirstSaveStarts()
        await store.send(.toggleControl(shortcut, true)) {
            $0.selectedControlIDs = [mute, shortcut]; $0.order = [mute, shortcut]
            $0.pendingLayoutSaves[studio.id] = .init(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [mute, shortcut])
        }
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
            isSetupRequired: false,
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
        await recorder.waitUntilFirstSaveStarts()
        await store.send(.toggleControl(shortcut, true)) {
            $0.selectedControlIDs = [mute, shortcut]; $0.order = [mute, shortcut]
            $0.pendingLayoutSaves[studio.id] = .init(macID: studio.id, selectedControlIDs: [mute, shortcut], order: [mute, shortcut])
        }
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
        var state = SettingsFeature.State(isSetupRequired: false, pairedMacs: [studio], selectedMacID: studio.id)
        state.isObservingConnectionEvents = true
        let controls = [descriptor(mute)]
        let store = TestStore(initialState: state) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.saveCatalog = { try await cacheRecorder.save(macID: $0, revision: $1, controls: $2) }
        }

        await store.send(.connectionEvent(.catalog(studio.id, 12, controls))) {
            $0.catalog = IdentifiedArray(uniqueElements: controls); $0.catalogRevision = 12
        }
        await store.receive(.catalogCacheSaveResponse(studio.id, 12, .success))
        #expect(await cacheRecorder.revisions == [12])
    }

    @Test func pairAnotherSuccessLoadsTheNewMacLayoutBeforeDelegating() async {
        let laptop = laptop
        let layout = MacDashboardLayout(macID: laptop.id, selectedControlIDs: [mute], order: [mute])
        var state = SettingsFeature.State(isSetupRequired: false, pairedMacs: [studio], selectedMacID: studio.id)
        state.pairing = PairingFeature.State()
        let store = TestStore(initialState: state) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.loadLayout = { _ in layout }
            $0.remotePersistence.loadCatalog = { _ in nil }
        }

        await store.send(.pairing(.presented(.delegate(.paired(laptop))))) {
            $0.pairing = nil; $0.pairedMacs = [studio, laptop]; $0.selectedMacID = laptop.id
            $0.selectionGeneration = 1; $0.catalog = []; $0.catalogRevision = 0; $0.selectedControlIDs = []; $0.order = []
        }
        await store.receive(.delegate(.paired(laptop)))
        await store.receive(.selectedMacDataLoaded(1, laptop.id, layout, nil)) {
            $0.selectedControlIDs = [mute]; $0.order = [mute]
        }
    }

    @Test func forgettingSelectedMacChoosesDeterministicFallbackAndDelegatesSelection() async {
        var state = SettingsFeature.State(isSetupRequired: false, pairedMacs: [studio, laptop], selectedMacID: studio.id)
        state.management = .init(mac: studio)
        let store = TestStore(initialState: state) { SettingsFeature() } withDependencies: {
            $0.remotePersistence.loadLayout = { _ in nil }
            $0.remotePersistence.loadCatalog = { _ in nil }
        }

        await store.send(.management(.presented(.delegate(.forgotten(studio.id))))) {
            $0.management = nil; $0.pairedMacs = [laptop]; $0.connectionStatuses[studio.id] = nil
        }
        await store.receive(.delegate(.macForgotten(studio.id)))
        await store.receive(.selectedMacChanged(laptop.id)) {
            $0.selectedMacID = laptop.id; $0.selectionGeneration = 1
            $0.catalog = []; $0.catalogRevision = 0; $0.selectedControlIDs = []; $0.order = []
        }
        await store.receive(.delegate(.selectedMacChanged(laptop)))
        await store.receive(.selectedMacDataLoaded(1, laptop.id, nil, nil))
    }

    @Test func forgettingLastMacDelegatesAllMacsRemoved() async {
        var state = SettingsFeature.State(isSetupRequired: false, pairedMacs: [studio], selectedMacID: studio.id)
        state.management = .init(mac: studio)
        let store = TestStore(initialState: state) { SettingsFeature() }

        await store.send(.management(.presented(.delegate(.forgotten(studio.id))))) {
            $0.management = nil; $0.pairedMacs = []; $0.selectedMacID = nil
            $0.connectionStatuses[studio.id] = nil; $0.catalog = []; $0.catalogRevision = 0
            $0.selectedControlIDs = []; $0.order = []
        }
        await store.receive(.delegate(.allMacsRemoved))
    }

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
