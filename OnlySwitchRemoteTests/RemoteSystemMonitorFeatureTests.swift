import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteSystemMonitorFeatureTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private let otherMacID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

    @Test func visibleAuthenticatedMonitorStartsStreamingAndAcceptsSelectedMacSnapshots() async {
        let snapshot = makeSnapshot()
        var state = RemoteSystemMonitorFeature.State()
        state.selectedMacID = macID
        state.connectionState = .authenticated
        let store = TestStore(initialState: state) { RemoteSystemMonitorFeature() } withDependencies: {
            $0.remoteConnection.setSystemMonitorStreaming = { enabled in
                #expect(enabled)
            }
        }

        await store.send(.visibilityChanged(true)) { $0.isVisible = true }
        await store.receive(.streamingResponse(.success(true))) { $0.isStreaming = true }
        await store.send(.connectionEvent(.systemMonitor(macID, snapshot))) {
            $0.snapshot = snapshot
            $0.history = .init(snapshots: [snapshot])
        }
    }

    @Test func invisibleOrOfflineMonitorDoesNotRequestAStream() async {
        var state = RemoteSystemMonitorFeature.State()
        state.selectedMacID = macID
        state.connectionState = .offline(nil)
        let store = TestStore(initialState: state) { RemoteSystemMonitorFeature() }

        await store.send(.visibilityChanged(true)) { $0.isVisible = true }
        await store.send(.connectionEvent(.systemMonitor(macID, makeSnapshot())))
    }

    @Test func mismatchedMacSnapshotsAreIgnored() async {
        var state = RemoteSystemMonitorFeature.State()
        state.selectedMacID = macID
        state.connectionState = .authenticated
        state.isVisible = true
        let store = TestStore(initialState: state) { RemoteSystemMonitorFeature() }

        await store.send(.connectionEvent(.systemMonitor(otherMacID, makeSnapshot())))
        #expect(store.state.snapshot == nil)
        #expect(store.state.history.snapshots.isEmpty)
    }

    @Test func leavingMonitorStopsStreamingImmediately() async {
        var state = RemoteSystemMonitorFeature.State()
        state.selectedMacID = macID
        state.connectionState = .authenticated
        state.isVisible = true
        state.isStreaming = true
        let store = TestStore(initialState: state) { RemoteSystemMonitorFeature() } withDependencies: {
            $0.remoteConnection.setSystemMonitorStreaming = { enabled in
                #expect(enabled == false)
            }
        }

        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
            $0.isStreaming = false
        }
    }

    @Test func unsupportedMonitorRecordsAvailabilityWithoutDisablingControls() async {
        var state = RemoteSystemMonitorFeature.State()
        state.selectedMacID = macID
        state.connectionState = .authenticated
        let store = TestStore(initialState: state) { RemoteSystemMonitorFeature() } withDependencies: {
            $0.remoteConnection.setSystemMonitorStreaming = { _ in
                throw RemoteProtocolError(code: .actionNotSupported, message: "System Monitor is unavailable on this Mac")
            }
        }

        await store.send(.visibilityChanged(true)) { $0.isVisible = true }
        await store.receive(.streamingResponse(.failure(.init(
            code: .actionNotSupported,
            message: "System Monitor is unavailable on this Mac"
        )))) {
            $0.availabilityMessage = "This Mac needs a newer OnlySwitch version to share System Monitor."
        }
    }

    @Test func onlySupportedMetricsExpand() async {
        let store = TestStore(initialState: RemoteSystemMonitorFeature.State()) { RemoteSystemMonitorFeature() }

        await store.send(.toggleExpandedMetric(.cpu)) { $0.expandedMetrics = [.cpu] }
        await store.send(.toggleExpandedMetric(.memory)) { $0.expandedMetrics = [.cpu, .memory] }
        await store.send(.toggleExpandedMetric(.network)) { $0.expandedMetrics = [.cpu, .memory, .network] }
        await store.send(.toggleExpandedMetric(.gpu))
        await store.send(.toggleExpandedMetric(.disk))
    }

    @Test func historyRetainsTheNewestSixtySnapshots() async {
        var state = RemoteSystemMonitorFeature.State()
        state.selectedMacID = macID
        state.connectionState = .authenticated
        state.isVisible = true
        let store = TestStore(initialState: state) { RemoteSystemMonitorFeature() }

        for index in 0 ... 60 {
            await store.send(.connectionEvent(.systemMonitor(macID, makeSnapshot(index)))) {
                let snapshot = makeSnapshot(index)
                $0.snapshot = snapshot
                $0.history.append(snapshot)
            }
        }

        #expect(store.state.history.snapshots.count == SystemMonitorHistory.maximumSampleCount)
        #expect(store.state.history.snapshots.first?.timestamp == makeSnapshot(1).timestamp)
        #expect(store.state.history.snapshots.last?.timestamp == makeSnapshot(60).timestamp)
    }

    private func makeSnapshot(_ index: Int = 0) -> SystemMonitorSnapshot {
        .init(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_800_000_000 + index)),
            cpuUsage: .available(Double(index) / 100),
            memory: .available(.init(totalBytes: 16_000, usedBytes: UInt64(index)))
        )
    }
}
