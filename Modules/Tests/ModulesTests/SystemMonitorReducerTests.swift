import ComposableArchitecture
import SystemMonitor
import Testing

struct SystemMonitorReducerTests {
    @Test func formatsNetworkRateUsingBinaryUnits() {
        #expect(SystemMonitorFormatter.rate(bytesPerSecond: 1_536) == "1.5 KB/s")
    }

    @Test func disabledMenuBarMetricsDoNotNeedBackgroundSampling() {
        #expect(SystemMonitorPreferences(menuBarMetrics: []).requiresBackgroundSampling == false)
    }

    @Test func historyRetainsTheMostRecentSixtySnapshots() {
        var history = SystemMonitorHistory()

        for second in 0 ... 60 {
            history.append(SystemMonitorSnapshot(timestamp: Date(timeIntervalSinceReferenceDate: Double(second))))
        }

        #expect(history.snapshots.count == 60)
        #expect(history.snapshots.first?.timestamp == Date(timeIntervalSinceReferenceDate: 1))
    }

    @MainActor
    @Test func visibleMonitorStartsSamplingAndTrimsHistory() async {
        let snapshots = (0 ... 60).map(fixture)
        let store = TestStore(initialState: SystemMonitorReducer.State()) {
            SystemMonitorReducer()
        } withDependencies: {
            $0.systemMonitor.snapshots = {
                AsyncThrowingStream { continuation in
                    for snapshot in snapshots {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                }
            }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
        }

        for snapshot in snapshots {
            await store.receive(.snapshotReceived(snapshot)) {
                $0.snapshot = snapshot
                $0.history.append(snapshot)
            }
        }

        #expect(store.state.history.snapshots.count == 60)
        #expect(store.state.history.snapshots.first?.timestamp == fixture(1).timestamp)
        await store.finish()
    }

    @MainActor
    @Test func hidingTheLastConsumerCancelsTheStream() async {
        let store = TestStore(initialState: .init()) {
            SystemMonitorReducer()
        } withDependencies: {
            $0.systemMonitor.snapshots = {
                AsyncThrowingStream { _ in }
            }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
        }
        await store.send(.visibilityChanged(false)) {
            $0.isVisible = false
        }
        await store.finish()
    }

    @MainActor
    @Test func onlySupportedMetricsCanBeExpanded() async {
        let store = TestStore(initialState: .init()) {
            SystemMonitorReducer()
        }

        await store.send(.toggleExpandedMetric(.cpu)) {
            $0.expandedMetrics = [.cpu]
        }
        await store.send(.toggleExpandedMetric(.gpu))
        await store.send(.toggleExpandedMetric(.cpu)) {
            $0.expandedMetrics = []
        }
    }

    @MainActor
    @Test func streamErrorsPreserveTheLastGoodSnapshot() async {
        let snapshot = fixture(0)
        let store = TestStore(initialState: .init()) {
            SystemMonitorReducer()
        } withDependencies: {
            $0.systemMonitor.snapshots = {
                AsyncThrowingStream { continuation in
                    continuation.yield(snapshot)
                    continuation.finish(throwing: MonitorTestError.failed)
                }
            }
        }

        await store.send(.visibilityChanged(true)) {
            $0.isVisible = true
        }
        await store.receive(.snapshotReceived(snapshot)) {
            $0.snapshot = snapshot
            $0.history.append(snapshot)
        }
        await store.receive(.streamFailed(MonitorTestError.failed.localizedDescription)) {
            $0.lastFailure = MonitorTestError.failed.localizedDescription
        }
        #expect(store.state.snapshot == snapshot)
        await store.finish()
    }

    private func fixture(_ second: Int) -> SystemMonitorSnapshot {
        SystemMonitorSnapshot(timestamp: Date(timeIntervalSinceReferenceDate: Double(second)))
    }
}

private enum MonitorTestError: LocalizedError {
    case failed

    var errorDescription: String? { "The monitor stream failed." }
}
