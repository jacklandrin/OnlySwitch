import ComposableArchitecture
import SystemMonitor
import Testing
@testable import OnlySwitch

struct OnlyControlSystemMonitorTests {
    @MainActor
    @Test
    func selectingMonitorMakesTheOnlyControlMonitorVisible() async {
        let store = TestStore(initialState: OnlyControlReducer.State()) {
            OnlyControlReducer()
        } withDependencies: {
            $0.systemMonitor.snapshots = { AsyncThrowingStream { _ in } }
        }

        await store.send(.selectedSectionChanged(.systemMonitor)) {
            $0.selectedSection = .systemMonitor
        }
        await store.receive(.systemMonitor(.visibilityChanged(true))) {
            $0.systemMonitor.isVisible = true
            $0.systemMonitor.isSampling = true
        }
        await store.send(.selectedSectionChanged(.controls)) {
            $0.selectedSection = .controls
        }
        await store.receive(.systemMonitor(.visibilityChanged(false))) {
            $0.systemMonitor.isVisible = false
            $0.systemMonitor.isSampling = false
        }
        await store.finish()
    }

    @MainActor
    @Test
    func hidingControlStopsMonitorSampling() async {
        let store = TestStore(initialState: .init(
            selectedSection: .systemMonitor,
            systemMonitor: .init(isVisible: true, isSampling: true)
        )) {
            OnlyControlReducer()
        } withDependencies: {
            $0.systemMonitor.snapshots = { AsyncThrowingStream { _ in } }
        }

        await store.send(.hideControl) {
            $0.blurRadius = 20
            $0.opacity = 0
        }
        await store.receive(.systemMonitor(.visibilityChanged(false))) {
            $0.systemMonitor.isVisible = false
            $0.systemMonitor.isSampling = false
        }
        await store.finish()
    }

    @MainActor
    @Test
    func disablingSelectedOptionalSectionReturnsToControls() async {
        let store = TestStore(initialState: .init(selectedSection: .authenticator)) {
            OnlyControlReducer()
        }

        await store.send(.availableSectionsChanged([.controls, .systemMonitor])) {
            $0.selectedSection = .controls
        }
    }
}
