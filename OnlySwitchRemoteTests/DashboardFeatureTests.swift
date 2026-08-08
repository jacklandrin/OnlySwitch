import ComposableArchitecture
import Foundation
import RemoteCore
import SwiftUI
import Testing
@testable import OnlySwitchRemote

@MainActor
struct DashboardFeatureTests {
    private let mac = PairedMac(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        displayName: "Studio",
        lastEndpointDescription: nil,
        lastConnectedAt: nil,
        requiresPairing: false
    )

    @Test func tileIconsUseFixedVisualSize() {
        #expect(ControlTileView.iconSize == 28)
    }

    @Test func compactWidthPortraitKeepsTwoColumns() {
        #expect(DashboardView.gridStrategy(
            horizontal: .compact,
            vertical: .regular
        ) == .fixed(count: 2))
    }

    @Test func compactHeightUsesDenserLandscapeGrid() {
        #expect(DashboardView.gridStrategy(
            horizontal: .compact,
            vertical: .compact
        ) == .adaptive(minimum: 180))
        #expect(DashboardView.gridStrategy(
            horizontal: .regular,
            vertical: .compact
        ) == .adaptive(minimum: 180))
    }

    @Test func regularLayoutPreservesExistingAdaptiveMinimum() {
        #expect(DashboardView.gridStrategy(
            horizontal: .regular,
            vertical: .regular
        ) == .adaptive(minimum: 160))
    }

    @Test func macPickerPreservesFullSelectedNameForAccessibility() {
        let longName = "p200300fe5700cdb61cf16e5542f6a6bc.dip0.t-ipconnect.de"
        let selected = PairedMac(
            id: UUID(),
            displayName: longName,
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        let picker = MacPickerView(
            macs: [selected],
            selectedMacID: selected.id,
            select: { _ in }
        )

        #expect(picker.selectedName == longName)
    }

    @Test func serverProcessingStatusIsAnnouncedAsWorking() {
        let processing = RemoteControlStatus(
            id: .darkMode,
            isAvailable: true,
            unavailableReason: nil,
            isOn: false,
            secondaryInformation: nil,
            isProcessing: true,
            revision: 1,
            updatedAt: .now
        )
        let tile = ControlTileView(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: .init(value: processing, isStale: false),
            macName: "Studio",
            isRequestInFlight: false,
            isEnabled: false,
            reduceMotion: true,
            action: {}
        )

        #expect(tile.accessibilityValue == "Working")
    }

    @Test func taskSubscribesOnlyToSelectedTiles() async {
        let subscriptions = DashboardSubscriptionRecorder()
        let state = DashboardFeature.State(
            pairedMacs: [],
            selectedMacID: nil,
            descriptors: [],
            statuses: [:],
            orderedSelectedIDs: [.darkMode, .mute],
            requestsInFlight: [],
            connectionState: .authenticated
        )
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.subscribe = { await subscriptions.record($0) }
        }

        await store.send(.task) { $0.isActive = true }
        await store.receive(.subscriptionStarted([.darkMode, .mute]))
        await store.finish()
        #expect(await subscriptions.values == [[.darkMode, .mute]])
    }

    @Test func disconnectMarksStatusStaleAndDisablesActions() async {
        let status = status(id: .darkMode, isOn: true, revision: 1)
        let state = DashboardFeature.State(
            pairedMacs: [mac],
            selectedMacID: mac.id,
            descriptors: [descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch)],
            statuses: [.darkMode: .init(value: status, isStale: false)],
            orderedSelectedIDs: [.darkMode],
            requestsInFlight: [],
            connectionState: .authenticated
        )
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.subscribe = { _ in }
        }

        await store.send(.connectionEvent(.offline(mac.id, "Mac went to sleep"))) {
            $0.connectionState = .offline("Mac went to sleep")
            $0.activeSessionID = nil
            $0.statuses[.darkMode]?.isStale = true
        }
        #expect(!store.state.canSendActions)
    }

    @Test func destructiveControlRequiresConfirmationBeforeSending() async {
        let sent = DashboardActionRecorder()
        let state = makeState(
            descriptor: descriptor(id: .emptyTrash, title: "Empty Trash", behavior: .button, destructive: true),
            status: status(id: .emptyTrash, isOn: nil, revision: 1)
        )
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.send = { try await sent.send($0) }
        }

        await store.send(.tileTapped(.emptyTrash)) {
            $0.alert = .confirmDestructive(controlID: .emptyTrash, controlTitle: "Empty Trash", macName: "Studio")
        }
        #expect(await sent.requests.isEmpty)
    }

    @Test func nonDestructiveSwitchWaitsForAuthoritativeStatus() async {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let oldStatus = status(id: .darkMode, isOn: false, revision: 4)
        let result = RemoteActionResult(
            requestID: requestID,
            result: .success(status(id: .darkMode, isOn: true, revision: 5))
        )
        let state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: oldStatus
        )
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.uuid = UUIDGenerator { requestID }
            $0.remoteConnection.send = { _ in result }
        }

        await store.send(.tileTapped(.darkMode)) {
            $0.requestsInFlight = [.darkMode]
            $0.requestIDs[.darkMode] = requestID
        }
        #expect(store.state.statuses[.darkMode]?.value == oldStatus)
        await store.receive(.actionResponse(.darkMode, requestID, .success(result))) {
            $0.requestsInFlight = []
            $0.requestIDs = [:]
            $0.statuses[.darkMode] = .init(value: self.status(id: .darkMode, isOn: true, revision: 5), isStale: false)
        }
    }

    @Test func duplicateAndOlderStatusRevisionsAreIgnored() async {
        let current = status(id: .darkMode, isOn: true, revision: 7)
        let state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: current
        )
        let store = TestStore(initialState: state) { DashboardFeature() }

        await store.send(.connectionEvent(.status(mac.id, status(id: .darkMode, isOn: false, revision: 7))))
        await store.send(.connectionEvent(.status(mac.id, status(id: .darkMode, isOn: false, revision: 6))))
        #expect(store.state.statuses[.darkMode]?.value == current)
    }

    @Test func firstLiveSnapshotsOverrideHigherRevisionCacheForNewSession() async {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let cachedDescriptor = descriptor(id: .darkMode, title: "Cached Dark Mode", behavior: .switch)
        let liveDescriptor = descriptor(id: .darkMode, title: "Live Dark Mode", behavior: .switch)
        var state = makeState(
            descriptor: cachedDescriptor,
            status: status(id: .darkMode, isOn: false, revision: 99)
        )
        state.catalogRevision = 99
        let liveStatus = status(id: .darkMode, isOn: true, revision: 1)
        let store = TestStore(initialState: state) { DashboardFeature() }

        await store.send(.connectionEvent(.sessionStarted(mac.id, sessionID))) {
            $0.activeSessionID = sessionID
            $0.awaitingInitialCatalog = true
            $0.liveStatusControlIDs = []
            $0.statuses[.darkMode]?.isStale = true
        }
        await store.send(.connectionEvent(.catalog(mac.id, 1, [liveDescriptor]))) {
            $0.catalogRevision = 1
            $0.descriptors = [liveDescriptor]
            $0.awaitingInitialCatalog = false
            $0.hasAcceptedLiveCatalog = true
        }
        await store.send(.connectionEvent(.statusSnapshot(mac.id, [liveStatus]))) {
            $0.statuses[.darkMode] = .init(value: liveStatus, isStale: false)
            $0.liveStatusControlIDs = [.darkMode]
        }

        await store.send(.connectionEvent(.catalog(mac.id, 1, [cachedDescriptor])))
        await store.send(.connectionEvent(.status(mac.id, status(id: .darkMode, isOn: false, revision: 1))))
        #expect(store.state.descriptors[id: .darkMode] == liveDescriptor)
        #expect(store.state.statuses[.darkMode]?.value == liveStatus)
    }

    @Test func catalogInvalidationPreservesTilesUntilSameRevisionSnapshotArrives() async {
        let current = descriptor(id: .darkMode, title: "Current", behavior: .switch)
        let refreshed = descriptor(id: .darkMode, title: "Refreshed", behavior: .switch)
        var state = makeState(descriptor: current, status: status(id: .darkMode, isOn: true, revision: 3))
        state.catalogRevision = 3
        state.awaitingInitialCatalog = false
        let store = TestStore(initialState: state) { DashboardFeature() }

        await store.send(.connectionEvent(.catalogInvalidated(mac.id, 4))) {
            $0.pendingCatalogRevision = 4
        }
        #expect(store.state.descriptors[id: .darkMode] == current)
        await store.send(.connectionEvent(.catalog(mac.id, 4, [refreshed]))) {
            $0.catalogRevision = 4
            $0.descriptors = [refreshed]
            $0.pendingCatalogRevision = nil
            $0.hasAcceptedLiveCatalog = true
        }
    }

    @Test func offlineRecoveryClearsPendingCatalogRefresh() async {
        var state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: true, revision: 3)
        )
        state.catalogRevision = 3
        state.pendingCatalogRevision = 4
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.subscribe = { _ in }
        }

        await store.send(.connectionEvent(.offline(mac.id, "Catalog refresh failed"))) {
            $0.connectionState = .offline("Catalog refresh failed")
            $0.activeSessionID = nil
            $0.pendingCatalogRevision = nil
            $0.statuses[.darkMode]?.isStale = true
        }

        #expect(store.state.canSendActions == false)
        let newSessionID = UUID()
        await store.send(.connectionEvent(.sessionStarted(mac.id, newSessionID))) {
            $0.activeSessionID = newSessionID
            $0.awaitingInitialCatalog = true
            $0.hasAcceptedLiveCatalog = false
            $0.liveStatusControlIDs = []
        }
        await store.send(.connectionEvent(.authenticated(mac.id))) {
            $0.connectionState = .authenticated
        }
        await store.receive(.subscriptionStarted([.darkMode]))
        await store.send(.connectionEvent(.catalog(mac.id, 4, Array(store.state.descriptors)))) {
            $0.catalogRevision = 4
            $0.awaitingInitialCatalog = false
            $0.hasAcceptedLiveCatalog = true
        }
        await store.send(.connectionEvent(.statusSnapshot(mac.id, [
            status(id: .darkMode, isOn: true, revision: 4),
        ]))) {
            $0.statuses[.darkMode] = .init(
                value: status(id: .darkMode, isOn: true, revision: 4),
                isStale: false
            )
            $0.liveStatusControlIDs = [.darkMode]
        }
        #expect(store.state.pendingCatalogRevision == nil)
        #expect(store.state.canSendActions)
    }

    @Test func newerPushedStatusIsAuthoritative() async {
        let state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: false, revision: 7)
        )
        let newer = status(id: .darkMode, isOn: true, revision: 8)
        let store = TestStore(initialState: state) { DashboardFeature() }

        await store.send(.connectionEvent(.status(mac.id, newer))) {
            $0.statuses[.darkMode] = .init(value: newer, isStale: false)
        }
    }

    @Test func actionFailureRestoresIdleStateAndShowsSafeError() async {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let failure = RemoteProtocolError(code: .executionFailed, message: "The Mac could not complete this action.")
        let state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: false, revision: 2)
        )
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.uuid = UUIDGenerator { requestID }
            $0.remoteConnection.send = { _ in throw failure }
        }

        await store.send(.tileTapped(.darkMode)) {
            $0.requestsInFlight = [.darkMode]
            $0.requestIDs[.darkMode] = requestID
        }
        await store.receive(.actionResponse(.darkMode, requestID, .failure(failure))) {
            $0.requestsInFlight = []
            $0.requestIDs = [:]
            $0.alert = .actionFailed(message: failure.message)
        }
        #expect(store.state.statuses[.darkMode]?.value.isOn == false)
    }

    @Test func timedOutActionRetriesOnlyAfterConfirmationWithSameRequestIdentity() async {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let sent = DashboardActionRecorder()
        let timeout = RemoteProtocolError(code: .requestTimedOut, message: "The Mac did not respond in time")
        let state = makeState(
            descriptor: descriptor(id: .emptyTrash, title: "Empty Trash", behavior: .button, destructive: true),
            status: status(id: .emptyTrash, isOn: nil, revision: 1)
        )
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.uuid = UUIDGenerator { requestID }
            $0.remoteConnection.send = {
                _ = try await sent.send($0)
                throw timeout
            }
        }

        await store.send(.tileTapped(.emptyTrash)) {
            $0.alert = .confirmDestructive(controlID: .emptyTrash, controlTitle: "Empty Trash", macName: "Studio")
        }
        await store.send(.alert(.presented(.confirmDestructive(.emptyTrash)))) {
            $0.alert = nil
            $0.requestsInFlight = [.emptyTrash]
            $0.requestIDs[.emptyTrash] = requestID
        }
        let invocation = RemoteActionInvocation(
            macID: mac.id,
            sessionID: store.state.activeSessionID!,
            request: .init(requestID: requestID, controlID: .emptyTrash, action: .trigger)
        )
        await store.receive(.actionCompleted(.emptyTrash, invocation, .failure(timeout))) {
            $0.requestsInFlight = []
            $0.requestIDs = [:]
            $0.retryInvocations[.emptyTrash] = invocation
            $0.alert = .actionTimedOut(controlID: .emptyTrash, destructive: true)
        }
        #expect(await sent.invocations == [invocation])

        await store.send(.alert(.presented(.retryTimedOut(.emptyTrash)))) {
            $0.alert = nil
            $0.retryInvocations[.emptyTrash] = nil
            $0.requestsInFlight = [.emptyTrash]
            $0.requestIDs[.emptyTrash] = requestID
        }
        await store.receive(.actionCompleted(.emptyTrash, invocation, .failure(timeout))) {
            $0.requestsInFlight = []
            $0.requestIDs = [:]
            $0.retryInvocations[.emptyTrash] = invocation
            $0.alert = .actionTimedOut(controlID: .emptyTrash, destructive: true)
        }
        #expect(await sent.invocations == [invocation, invocation])
    }

    @Test func goingOfflineCancelsActiveActionAndIgnoresItsLateResponse() async {
        let probe = DashboardActionCancellationProbe()
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
        let state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: false, revision: 2)
        )
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.uuid = UUIDGenerator { requestID }
            $0.remoteConnection.send = { try await probe.send($0) }
        }

        await store.send(.tileTapped(.darkMode)) {
            $0.requestsInFlight = [.darkMode]
            $0.requestIDs[.darkMode] = requestID
        }
        await probe.waitUntilStarted()
        await store.send(.connectionEvent(.offline(mac.id, "Sleeping"))) {
            $0.connectionState = .offline("Sleeping")
            $0.activeSessionID = nil
            $0.statuses[.darkMode]?.isStale = true
            $0.requestsInFlight = []
            $0.requestIDs = [:]
        }
        await probe.waitUntilCancelled()
        #expect(await probe.wasCancelled)
    }

    @Test func switchingMacCancelsActiveAction() async {
        let probe = DashboardActionCancellationProbe()
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000405")!
        let other = PairedMac(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            displayName: "Laptop",
            lastEndpointDescription: nil,
            lastConnectedAt: nil,
            requiresPairing: false
        )
        let state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: false, revision: 2)
        )
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.uuid = UUIDGenerator { requestID }
            $0.remoteConnection.send = { try await probe.send($0) }
            $0.remoteConnection.subscribe = { _ in }
            $0.remotePersistence.loadLayout = { _ in nil }
            $0.remotePersistence.loadCatalog = { _ in nil }
            $0.remotePersistence.loadStatuses = { _ in nil }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.tileTapped(.darkMode))
        await probe.waitUntilStarted()
        await store.send(.synchronize([mac, other], other.id, .connecting))
        #expect(await probe.cancellationObserved())
    }

    @Test func anotherMacEventsCannotOverwriteSelectedMac() async {
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let current = status(id: .darkMode, isOn: false, revision: 2)
        let state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: current
        )
        let store = TestStore(initialState: state) { DashboardFeature() }

        await store.send(.connectionEvent(.status(otherID, status(id: .darkMode, isOn: true, revision: 99))))
        #expect(store.state.statuses[.darkMode]?.value == current)
    }

    @Test func delayedEqualRevisionCacheCannotOverwriteLiveStatus() async {
        let live = status(id: .darkMode, isOn: true, revision: 9)
        let cached = status(id: .darkMode, isOn: false, revision: 9)
        var state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: live
        )
        state.selectionGeneration = 2
        let layout = MacDashboardLayout(macID: mac.id, selectedControlIDs: [.darkMode], order: [.darkMode])
        let cache = RemoteCatalogCache(revision: 1, controls: Array(state.descriptors))
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.subscribe = { _ in }
        }

        await store.send(.selectedDataLoaded(2, mac.id, .success(layout, cache, [cached]))) {
            $0.catalogRevision = 1
        }
        #expect(store.state.statuses[.darkMode] == .init(value: live, isStale: false))
        await store.receive(.subscriptionStarted([.darkMode]))
    }

    @Test func delayedHigherRevisionCacheCannotOverwriteNewSessionSnapshot() async {
        let live = status(id: .darkMode, isOn: true, revision: 1)
        let cached = status(id: .darkMode, isOn: false, revision: 99)
        var state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: false, revision: 88)
        )
        state.selectionGeneration = 2
        state.activeSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000404")!
        state.liveStatusControlIDs = []
        let layout = MacDashboardLayout(macID: mac.id, selectedControlIDs: [.darkMode], order: [.darkMode])
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.subscribe = { _ in }
        }

        await store.send(.connectionEvent(.statusSnapshot(mac.id, [live]))) {
            $0.statuses[.darkMode] = .init(value: live, isStale: false)
            $0.liveStatusControlIDs = [.darkMode]
        }
        await store.send(.selectedDataLoaded(2, mac.id, .success(layout, nil, [cached])))
        #expect(store.state.statuses[.darkMode]?.value == live)
        await store.receive(.subscriptionStarted([.darkMode]))
    }

    @Test func delayedHigherRevisionCatalogCacheCannotOverwriteAcceptedSessionCatalog() async {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000405")!
        let liveDescriptor = descriptor(id: .darkMode, title: "Live Dark Mode", behavior: .switch)
        let cachedDescriptor = descriptor(id: .darkMode, title: "Cached Dark Mode", behavior: .switch)
        var state = makeState(
            descriptor: cachedDescriptor,
            status: status(id: .darkMode, isOn: true, revision: 1)
        )
        state.catalogRevision = 88
        state.selectionGeneration = 2
        state.hasAcceptedLiveCatalog = true
        let layout = MacDashboardLayout(macID: mac.id, selectedControlIDs: [.darkMode], order: [.darkMode])
        let cache = RemoteCatalogCache(revision: 99, controls: [cachedDescriptor])
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.subscribe = { _ in }
        }

        await store.send(.connectionEvent(.sessionStarted(mac.id, sessionID))) {
            $0.activeSessionID = sessionID
            $0.awaitingInitialCatalog = true
            $0.hasAcceptedLiveCatalog = false
            $0.liveStatusControlIDs = []
            $0.statuses[.darkMode]?.isStale = true
        }
        await store.send(.connectionEvent(.catalog(mac.id, 1, [liveDescriptor]))) {
            $0.catalogRevision = 1
            $0.descriptors = [liveDescriptor]
            $0.awaitingInitialCatalog = false
            $0.hasAcceptedLiveCatalog = true
        }
        await store.send(.selectedDataLoaded(2, mac.id, .success(layout, cache, [])))

        #expect(store.state.catalogRevision == 1)
        #expect(store.state.descriptors[id: .darkMode] == liveDescriptor)
        await store.receive(.subscriptionStarted([.darkMode]))
    }

    @Test func catalogRefreshBoundariesDisableActions() async {
        let initialRecorder = DashboardActionRecorder()
        var awaitingState = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: false, revision: 1)
        )
        awaitingState.awaitingInitialCatalog = true
        let awaitingStore = TestStore(initialState: awaitingState) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.send = { try await initialRecorder.send($0) }
        }

        await awaitingStore.send(.tileTapped(.darkMode))
        #expect(await initialRecorder.requests.isEmpty)

        let invalidationRecorder = DashboardActionRecorder()
        var invalidatedState = makeState(
            descriptor: descriptor(id: .emptyTrash, title: "Empty Trash", behavior: .button, destructive: true),
            status: status(id: .emptyTrash, isOn: nil, revision: 1)
        )
        invalidatedState.pendingCatalogRevision = 2
        let invalidatedStore = TestStore(initialState: invalidatedState) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.send = { try await invalidationRecorder.send($0) }
        }

        await invalidatedStore.send(.tileTapped(.emptyTrash))
        #expect(invalidatedStore.state.alert == nil)
        #expect(await invalidationRecorder.requests.isEmpty)
    }

    @Test func delayedOlderCatalogCacheCannotOverwriteLiveCatalog() async {
        let liveDescriptor = descriptor(id: .darkMode, title: "Live Dark Mode", behavior: .switch)
        let cachedDescriptor = descriptor(id: .darkMode, title: "Cached Dark Mode", behavior: .switch)
        var state = makeState(
            descriptor: liveDescriptor,
            status: status(id: .darkMode, isOn: true, revision: 9)
        )
        state.catalogRevision = 10
        state.selectionGeneration = 2
        let layout = MacDashboardLayout(macID: mac.id, selectedControlIDs: [.darkMode], order: [.darkMode])
        let cache = RemoteCatalogCache(revision: 9, controls: [cachedDescriptor])
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.subscribe = { _ in }
        }

        await store.send(.selectedDataLoaded(2, mac.id, .success(layout, cache, [])))
        #expect(store.state.catalogRevision == 10)
        #expect(store.state.descriptors[id: .darkMode] == liveDescriptor)
        await store.receive(.subscriptionStarted([.darkMode]))
    }

    @Test func delayedCacheFailureCannotClearLiveData() async {
        let liveDescriptor = descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch)
        let liveStatus = status(id: .darkMode, isOn: true, revision: 9)
        var state = makeState(descriptor: liveDescriptor, status: liveStatus)
        state.catalogRevision = 10
        state.selectionGeneration = 2
        let store = TestStore(initialState: state) { DashboardFeature() } withDependencies: {
            $0.remoteConnection.subscribe = { _ in }
        }

        await store.send(.selectedDataLoaded(2, mac.id, .failure))
        #expect(store.state.catalogRevision == 10)
        #expect(store.state.descriptors[id: .darkMode] == liveDescriptor)
        #expect(store.state.statuses[.darkMode]?.value == liveStatus)
        await store.receive(.subscriptionStarted([.darkMode]))
    }

    @Test func lateFailureForOlderRequestCannotAffectNewerRequest() async {
        let oldRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let newRequestID = UUID(uuidString: "00000000-0000-0000-0000-000000000304")!
        let failure = RemoteProtocolError(code: .requestTimedOut, message: "Timed out")
        var state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: false, revision: 2)
        )
        state.requestsInFlight = [.darkMode]
        state.requestIDs[.darkMode] = newRequestID
        let store = TestStore(initialState: state) { DashboardFeature() }

        await store.send(.actionResponse(.darkMode, oldRequestID, .failure(failure)))
        #expect(store.state.requestsInFlight == [.darkMode])
        #expect(store.state.requestIDs[.darkMode] == newRequestID)
        #expect(store.state.alert == nil)
    }

    @Test func lateFailureAfterDisconnectDoesNotShowAlert() async {
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000305")!
        let failure = RemoteProtocolError(code: .requestTimedOut, message: "Timed out")
        var state = makeState(
            descriptor: descriptor(id: .darkMode, title: "Dark Mode", behavior: .switch),
            status: status(id: .darkMode, isOn: false, revision: 2)
        )
        state.connectionState = .offline(nil)
        let store = TestStore(initialState: state) { DashboardFeature() }

        await store.send(.actionResponse(.darkMode, requestID, .failure(failure)))
        #expect(store.state.alert == nil)
    }

    private func makeState(
        descriptor: RemoteControlDescriptor,
        status: RemoteControlStatus
    ) -> DashboardFeature.State {
        var state = DashboardFeature.State(
            pairedMacs: [mac],
            selectedMacID: mac.id,
            descriptors: [descriptor],
            statuses: [status.id: .init(value: status, isStale: false)],
            orderedSelectedIDs: [descriptor.id],
            requestsInFlight: [],
            connectionState: .authenticated
        )
        state.activeSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000400")!
        state.liveStatusControlIDs = [descriptor.id]
        return state
    }

    private func descriptor(
        id: RemoteControlID,
        title: String,
        behavior: RemoteControlDescriptor.Behavior,
        destructive: Bool = false
    ) -> RemoteControlDescriptor {
        .init(
            id: id,
            title: title,
            behavior: behavior,
            icon: .systemSymbol("switch.2"),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: destructive,
            supportsStatus: behavior != .button,
            supportsSecondaryInformation: false
        )
    }

    private func status(
        id: RemoteControlID,
        isOn: Bool?,
        revision: UInt64
    ) -> RemoteControlStatus {
        .init(
            id: id,
            isAvailable: true,
            unavailableReason: nil,
            isOn: isOn,
            secondaryInformation: nil,
            isProcessing: false,
            revision: revision,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(revision))
        )
    }
}

actor DashboardSubscriptionRecorder {
    private(set) var values: [Set<RemoteControlID>] = []
    func record(_ value: Set<RemoteControlID>) { values.append(value) }
}

private actor DashboardActionRecorder {
    private(set) var invocations: [RemoteActionInvocation] = []
    var requests: [RemoteActionRequest] { invocations.map(\.request) }
    func send(_ invocation: RemoteActionInvocation) throws -> RemoteActionResult {
        invocations.append(invocation)
        return .init(requestID: invocation.request.requestID, result: .success(nil))
    }
}

private actor DashboardActionCancellationProbe {
    private var started = false
    private(set) var wasCancelled = false

    func send(_ invocation: RemoteActionInvocation) async throws -> RemoteActionResult {
        started = true
        do {
            try await Task.sleep(for: .seconds(60))
            return .init(requestID: invocation.request.requestID, result: .success(nil))
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }

    func waitUntilStarted() async {
        while started == false { await Task.yield() }
    }

    func waitUntilCancelled() async {
        while wasCancelled == false { await Task.yield() }
    }

    func cancellationObserved() async -> Bool {
        for _ in 0..<100 where wasCancelled == false { await Task.yield() }
        return wasCancelled
    }
}
