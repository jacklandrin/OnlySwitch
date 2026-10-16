import ComposableArchitecture
import Testing
@testable import OnlySwitch

@MainActor
struct DockPreviewFeatureTests {
    @Test
    func enablingRequestsAuthorizationAndRemainsStoppedWhenDenied() async {
        let store = TestStore(initialState: DockPreviewFeature.State()) {
            DockPreviewFeature()
        } withDependencies: {
            $0.dockPreview.authorizationStatus = { .init(accessibility: false, screenRecording: false) }
            $0.dockPreview.requestAuthorization = { .init(accessibility: false, screenRecording: false) }
        }

        await store.send(.enabledChanged(true)) {
            $0.isEnabled = true
            $0.authorization = .init(accessibility: false, screenRecording: false)
            $0.status = .requestingPermission
        }
        await store.receive(\.authorizationChanged) {
            $0.isEnabled = false
            $0.status = .permissionRequired
            $0.showPermissionHelp = true
        }
        await store.finish()
    }

    @Test
    func startupWithSavedIntentChecksWithoutPrompting() async {
        let store = TestStore(initialState: DockPreviewFeature.State()) {
            DockPreviewFeature()
        } withDependencies: {
            $0.dockPreview.authorizationStatus = { .init(accessibility: false, screenRecording: true) }
        }

        await store.send(.startup(isEnabled: true)) {
            $0.isEnabled = true
        }
        await store.receive(\.authorizationChanged) {
            $0.isEnabled = false
            $0.authorization = .init(accessibility: false, screenRecording: true)
            $0.status = .permissionRequired
        }
        await store.finish()
    }

    @Test
    func disablingClearsPreviewAndStopsObservation() async {
        let window = DockPreviewWindow(id: 1, title: "Document", pid: 42, frame: .zero, isActivatable: true)
        let state = DockPreviewFeature.State(
            isEnabled: true,
            authorization: .authorized,
            isObserving: true,
            preview: .init(
                generation: 1,
                appName: "TextEdit",
                itemFrame: .zero,
                screenFrame: .zero,
                windows: [window]
            )
        )
        let store = TestStore(initialState: state) { DockPreviewFeature() }

        await store.send(.enabledChanged(false)) {
            $0.isEnabled = false
            $0.authorization = .unknown
            $0.isObserving = false
            $0.preview = nil
            $0.status = .idle
            $0.hoverGeneration = 1
        }
        await store.finish()
    }

    @Test
    func lateWindowResultsFromAnOlderHoverAreDiscarded() async {
        let hover = DockHoverEvent(pid: 9, appName: "Preview", itemFrame: .zero, screenFrame: .zero)
        let store = TestStore(initialState: .init(
            isEnabled: true,
            authorization: .authorized,
            isObserving: true,
            hoverGeneration: 2
        )) { DockPreviewFeature() }

        await store.send(.windowsLoaded(generation: 1, hover: hover, result: .success([
            .init(id: 2, title: "Old", pid: 9, frame: .zero, isActivatable: true)
        ])))
        #expect(store.state.preview == nil)
    }

    @Test
    func emptyWindowResultsNeverCreateAPreview() async {
        let hover = DockHoverEvent(pid: 9, appName: "Preview", itemFrame: .zero, screenFrame: .zero)
        let store = TestStore(initialState: .init(
            isEnabled: true,
            authorization: .authorized,
            isObserving: true,
            hoverGeneration: 1
        )) { DockPreviewFeature() }

        await store.send(.windowsLoaded(generation: 1, hover: hover, result: .success([])))
        #expect(store.state.preview == nil)
    }

    @Test
    func lateHoverAfterStopCannotRestartWindowLoading() async {
        let hover = DockHoverEvent(pid: 9, appName: "Preview", itemFrame: .zero, screenFrame: .zero)
        let store = TestStore(initialState: DockPreviewFeature.State()) {
            DockPreviewFeature()
        }

        await store.send(.hovered(hover))
        #expect(store.state.preview == nil)
        #expect(store.state.status == .idle)
    }

    @Test
    func windowListingFailureShowsAnErrorPreview() async {
        let hover = DockHoverEvent(
            pid: 9,
            appName: "Preview",
            itemFrame: CGRect(x: 100, y: 0, width: 40, height: 40),
            screenFrame: CGRect(x: 0, y: 40, width: 800, height: 560)
        )
        let store = TestStore(initialState: .init(
            isEnabled: true,
            authorization: .authorized,
            isObserving: true,
            hoverGeneration: 1
        )) { DockPreviewFeature() }

        await store.send(.windowsLoaded(generation: 1, hover: hover, result: .failure(.windowListing))) {
            $0.preview = .init(
                generation: 1,
                appName: "Preview",
                itemFrame: hover.itemFrame,
                screenFrame: hover.screenFrame,
                windows: []
            )
            $0.status = .captureFailed
        }
    }

    @Test
    func activationFailureKeepsThePreviewAvailable() async {
        let window = DockPreviewWindow(id: 1, title: "Document", pid: 42, frame: .zero, isActivatable: true)
        let state = DockPreviewFeature.State(
            isEnabled: true,
            authorization: .authorized,
            isObserving: true,
            preview: .init(
                generation: 1,
                appName: "TextEdit",
                itemFrame: .zero,
                screenFrame: .zero,
                windows: [window]
            )
        )
        let store = TestStore(initialState: state) { DockPreviewFeature() } withDependencies: {
            $0.dockPreview.activate = { _ in throw DockPreviewFailure.activation }
        }

        await store.send(.windowTapped(window.id))
        await store.receive(\.activationFinished) {
            $0.status = .activationFailed
        }
        #expect(store.state.preview?.windows.count == 1)
    }

    @Test
    func sideDockNearBottomPlacesPanelBesideTheIcon() {
        let frame = DockPreviewPanelController.frame(
            size: CGSize(width: 240, height: 164),
            item: CGRect(x: 0, y: 48, width: 40, height: 40),
            visibleScreen: CGRect(x: 40, y: 40, width: 760, height: 560)
        )
        #expect(frame.minX == 48)
        #expect(frame.minY >= 40)
        #expect(frame.maxY <= 600)
    }
}
