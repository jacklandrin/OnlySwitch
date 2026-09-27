import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteSystemMonitorConfigurationFeatureTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private let otherMacID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!

    @Test func defaultMonitorLayoutShowsAllWidgetsInStableOrder() {
        let layout = MacSystemMonitorLayout.default(macID: macID)

        #expect(layout.visibleMetrics == Set(SystemMonitorMetric.allCases))
        #expect(layout.orderedVisibleMetrics == [.cpu, .gpu, .memory, .disk, .network])
    }

    @Test func decodingMalformedLegacyLayoutNormalizesKnownMetricsAndOrder() throws {
        let json = """
        {
          "macID": "\(macID.uuidString)",
          "visibleMetrics": ["memory", "unknown", "memory"],
          "order": ["disk", "unknown", "memory", "disk"]
        }
        """

        let layout = try JSONDecoder().decode(MacSystemMonitorLayout.self, from: Data(json.utf8))

        #expect(layout.visibleMetrics == [.memory])
        #expect(layout.order == [.disk, .memory, .cpu, .gpu, .network])
        #expect(layout.orderedVisibleMetrics == [.memory])
    }

    @Test func visibilityAndReorderingKeepTheLayoutDeterministic() {
        var layout = MacSystemMonitorLayout.default(macID: macID)

        layout.setVisible(.disk, isVisible: false)
        layout.move(from: IndexSet(integer: 2), to: 0)

        #expect(layout.visibleMetrics.contains(.disk) == false)
        #expect(layout.order == [.memory, .cpu, .gpu, .disk, .network])
        #expect(layout.orderedVisibleMetrics == [.memory, .cpu, .gpu, .network])
    }

    @Test func configurationPersistsVisibilityAndReorderingForOnlyItsMac() async {
        let initial = MacSystemMonitorLayout.default(macID: macID)
        let store = TestStore(
            initialState: RemoteSystemMonitorConfigurationFeature.State(layout: initial)
        ) {
            RemoteSystemMonitorConfigurationFeature()
        } withDependencies: {
            $0.remotePersistence.saveSystemMonitorLayout = { layout in
                #expect(layout.macID == self.macID)
            }
        }

        await store.send(.setVisible(.disk, false)) {
            $0.layout.visibleMetrics.remove(.disk)
        }
        await store.receive(.delegate(.layoutChanged(.init(
            macID: macID,
            visibleMetrics: [.cpu, .gpu, .memory, .network],
            order: [.cpu, .gpu, .memory, .disk, .network]
        ))))
        await store.receive(.saveResponse(.success))

        await store.send(.move(IndexSet(integer: 2), 0)) {
            $0.layout.order = [.memory, .cpu, .gpu, .disk, .network]
        }
        await store.receive(.delegate(.layoutChanged(.init(
            macID: macID,
            visibleMetrics: [.cpu, .gpu, .memory, .network],
            order: [.memory, .cpu, .gpu, .disk, .network]
        ))))
        await store.receive(.saveResponse(.success))

        let otherLayout = MacSystemMonitorLayout.default(macID: otherMacID)
        #expect(otherLayout.orderedVisibleMetrics == [.cpu, .gpu, .memory, .disk, .network])
        #expect(otherLayout.visibleMetrics.contains(.disk))
    }

    @Test func failedConfigurationSaveRetainsTheEditAndCanRetry() async {
        let calls = LockIsolated(0)
        let store = TestStore(
            initialState: RemoteSystemMonitorConfigurationFeature.State(
                layout: .default(macID: macID)
            )
        ) {
            RemoteSystemMonitorConfigurationFeature()
        } withDependencies: {
            $0.remotePersistence.saveSystemMonitorLayout = { layout in
                calls.withValue { $0 += 1 }
                if calls.value == 1 { throw TestPersistenceError.failed }
                #expect(layout.visibleMetrics.contains(.network) == false)
            }
        }

        await store.send(.setVisible(.network, false)) {
            $0.layout.visibleMetrics.remove(.network)
        }
        await store.receive(.delegate(.layoutChanged(.init(
            macID: macID,
            visibleMetrics: [.cpu, .gpu, .memory, .disk],
            order: [.cpu, .gpu, .memory, .disk, .network]
        ))))
        await store.receive(.saveResponse(.failure)) {
            $0.isSaveFailed = true
        }
        await store.send(.retrySave) {
            $0.isSaveFailed = false
        }
        await store.receive(.saveResponse(.success))

        #expect(store.state.layout.visibleMetrics.contains(.network) == false)
        #expect(calls.value == 2)
    }
}

private enum TestPersistenceError: Error {
    case failed
}
