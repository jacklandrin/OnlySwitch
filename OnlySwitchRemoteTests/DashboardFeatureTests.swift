import ComposableArchitecture
import Foundation
import RemoteCore
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
            $0.remoteConnection.subscribe = { try await subscriptions.record($0) }
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
        let store = TestStore(initialState: state) { DashboardFeature() }

        await store.send(.connectionEvent(.offline(mac.id, "Mac went to sleep"))) {
            $0.connectionState = .offline("Mac went to sleep")
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
        .init(
            pairedMacs: [mac],
            selectedMacID: mac.id,
            descriptors: [descriptor],
            statuses: [status.id: .init(value: status, isStale: false)],
            orderedSelectedIDs: [descriptor.id],
            requestsInFlight: [],
            connectionState: .authenticated
        )
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
    private(set) var requests: [RemoteActionRequest] = []
    func send(_ request: RemoteActionRequest) throws -> RemoteActionResult {
        requests.append(request)
        return .init(requestID: request.requestID, result: .success(nil))
    }
}
