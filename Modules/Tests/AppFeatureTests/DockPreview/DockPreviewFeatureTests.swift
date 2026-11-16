import ComposableArchitecture
import Foundation
import Testing
@testable import AppFeature

@MainActor
struct DockPreviewFeatureTests {
    @Test
    func permissionRevocationClearsTheCurrentHover() async {
        let hover = DockHoverEvent(pid: 42, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero)
        let store = TestStore(initialState: DockPreviewFeature.State(
            isEnabled: true, authorization: .authorized, isObserving: true, hover: hover
        )) { DockPreviewFeature() }

        await store.send(.authorizationChanged(.unknown, requested: false)) {
            $0.isEnabled = false
            $0.authorization = .unknown
            $0.isObserving = false
            $0.hover = nil
            $0.status = .permissionRequired
        }
        await store.finish()
    }

    private func unsettled(_ hover: DockHoverEvent) -> DockHoverEvent {
        var hover = hover
        hover.isSettled = false
        return hover
    }

    /// Feeds `count` identical direct hits and returns every update.
    private func feed(
        _ stabilizer: inout DockHoverStabilizer,
        _ hover: DockHoverEvent?,
        times count: Int
    ) -> [DockHoverStabilizer.Update] {
        (0..<count).map { _ in stabilizer.update(hover) }
    }

    @Test
    func newAppLoadsAfterTwoHitsButSettlesPositionLater() {
        var stabilizer = DockHoverStabilizer()
        var hover = DockHoverEvent(
            pid: 42, appName: "TextEdit",
            itemFrame: CGRect(x: 500, y: -40, width: 64, height: 64),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        // Window loading starts on the second hit even while the Dock is
        // still revealing, but the event is marked unsettled.
        #expect(stabilizer.update(hover) == .unchanged)
        hover.itemFrame.origin.y = -10
        #expect(stabilizer.update(hover) == .changed(unsettled(hover)))
        hover.itemFrame.origin.y = 16
        #expect(feed(&stabilizer, hover, times: 4) == Array(repeating: .unchanged, count: 4))
        #expect(stabilizer.update(hover) == .changed(hover))
        #expect(stabilizer.update(hover) == .unchanged)

        // After settling, geometry changes for the same app are only emitted
        // once stable, so a visible preview never jumps to a transient frame.
        hover.itemFrame.size.height = 96
        #expect(feed(&stabilizer, hover, times: 4) == Array(repeating: .unchanged, count: 4))
        #expect(stabilizer.update(hover) == .changed(hover))
        #expect(stabilizer.update(nil) == .changed(nil))
        #expect(stabilizer.update(hover) == .unchanged)
        #expect(stabilizer.update(hover) == .changed(unsettled(hover)))
    }

    @Test
    func crossingAnIconWithASingleHitNeverLoadsIt() {
        var stabilizer = DockHoverStabilizer()
        let first = DockHoverEvent(pid: 42, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero)
        var second = first
        second.pid = 43
        second.appName = "Notes"
        second.itemFrame.origin.x = 64
        var third = second
        third.pid = 44
        third.itemFrame.origin.x = 128
        #expect(stabilizer.update(first) == .unchanged)
        #expect(stabilizer.update(second) == .unchanged)
        #expect(stabilizer.update(third) == .unchanged)
        #expect(stabilizer.update(third) == .changed(unsettled(third)))
    }

    @Test
    func movingToAnotherAppEmitsItUnsettled() {
        var stabilizer = DockHoverStabilizer()
        let first = DockHoverEvent(pid: 42, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero)
        var second = first
        second.pid = 43
        second.appName = "Notes"
        second.itemFrame.origin.x = 64
        #expect(feed(&stabilizer, first, times: 5).last == .changed(first))
        #expect(stabilizer.update(second) == .unchanged)
        #expect(stabilizer.update(second) == .changed(unsettled(second)))
        #expect(feed(&stabilizer, second, times: 3).last == .changed(second))
    }

    @Test
    func leavingBeforeDockSettlesClearsTheUnsettledHover() {
        var stabilizer = DockHoverStabilizer()
        let hover = DockHoverEvent(pid: 42, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero)
        #expect(feed(&stabilizer, hover, times: 2).last == .changed(unsettled(hover)))
        #expect(stabilizer.update(nil) == .changed(nil))
        #expect(feed(&stabilizer, hover, times: 2).last == .changed(unsettled(hover)))
        #expect(feed(&stabilizer, hover, times: 2) == [.unchanged, .unchanged])
        #expect(stabilizer.update(hover) == .changed(hover))
    }

    @Test
    func exitGraceDoesNotCountAsStableDockGeometry() {
        var stabilizer = DockHoverStabilizer()
        let hover = DockHoverEvent(pid: 42, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero)
        #expect(feed(&stabilizer, hover, times: 2).last == .changed(unsettled(hover)))
        for _ in 0..<5 {
            #expect(stabilizer.update(hover, isDirectHit: false) == .unchanged)
        }
        #expect(feed(&stabilizer, hover, times: 4) == Array(repeating: .unchanged, count: 4))
        #expect(stabilizer.update(hover) == .changed(hover))
        #expect(stabilizer.update(hover, isDirectHit: false) == .unchanged)
        #expect(stabilizer.update(nil) == .changed(nil))
    }

    @Test
    func unsettledHoverLoadsWindowsButKeepsPreviewHiddenUntilSettled() async {
        var hover = DockHoverEvent(pid: 42, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero)
        hover.isSettled = false
        var settled = hover
        settled.isSettled = true
        settled.itemFrame = CGRect(x: 500, y: 16, width: 64, height: 64)
        let window = DockPreviewWindow(id: 1, title: "Document", pid: 42, frame: .zero, isActivatable: true)
        let store = TestStore(initialState: DockPreviewFeature.State(
            isEnabled: true, authorization: .authorized, isObserving: true
        )) { DockPreviewFeature() } withDependencies: {
            $0.dockPreview.windows = { _ in [window] }
            $0.dockPreview.capture = { _ in Data([1]) }
        }

        await store.send(.hovered(hover)) {
            $0.hoverGeneration = 1
            $0.hover = hover
            $0.status = .loading
        }
        await store.receive(\.windowsLoaded) {
            $0.preview = .init(generation: 1, appName: "TextEdit", itemFrame: .zero,
                               screenFrame: .zero, windows: [window], isPositionSettled: false)
            $0.status = .idle
        }
        await store.receive(\.thumbnailLoaded) {
            $0.preview?.windows[0].thumbnailData = Data([1])
        }
        #expect(!DockPreviewPanelController.isPresentable(store.state.preview!, status: store.state.status))

        await store.send(.hovered(settled)) {
            $0.hover = settled
            $0.preview?.itemFrame = settled.itemFrame
            $0.preview?.isPositionSettled = true
        }
        #expect(DockPreviewPanelController.isPresentable(store.state.preview!, status: store.state.status))
        await store.finish()
    }

    @Test
    func sameAppGeometryMovesPreviewWithoutReloadingWindows() async {
        let original = DockHoverEvent(pid: 42, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero)
        var moved = original
        moved.itemFrame = CGRect(x: 500, y: 16, width: 96, height: 96)
        let window = DockPreviewWindow(
            id: 1, title: "Document", pid: 42, frame: .zero,
            isActivatable: true, thumbnailData: Data([1, 2, 3])
        )
        let store = TestStore(initialState: DockPreviewFeature.State(
            isEnabled: true, authorization: .authorized, isObserving: true,
            hoverGeneration: 1, hover: original,
            preview: .init(generation: 1, appName: original.appName,
                           itemFrame: original.itemFrame, screenFrame: original.screenFrame,
                           windows: [window])
        )) { DockPreviewFeature() }

        await store.send(.hovered(moved)) {
            $0.hover = moved
            $0.preview?.itemFrame = moved.itemFrame
        }
        #expect(store.state.preview?.windows == [window])
        #expect(store.state.hoverGeneration == 1)
        await store.finish()
    }

    @Test
    func catalogResultUsesLatestGeometryAndDismissalSurvivesMovement() async {
        let original = DockHoverEvent(pid: 42, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero)
        var moved = original
        moved.itemFrame = CGRect(x: 500, y: 16, width: 96, height: 96)
        let store = TestStore(initialState: DockPreviewFeature.State(
            isEnabled: true, authorization: .authorized, isObserving: true,
            hoverGeneration: 1, hover: original, status: .loading
        )) { DockPreviewFeature() }

        await store.send(.hovered(moved)) { $0.hover = moved }
        await store.send(.windowsLoaded(generation: 1, hover: original, result: .failure(.windowListing))) {
            $0.preview = .init(generation: 1, appName: moved.appName,
                               itemFrame: moved.itemFrame, screenFrame: moved.screenFrame, windows: [])
            $0.status = .captureFailed
        }
        await store.send(.escapePressed) {
            $0.hoverGeneration = 2
            $0.preview = nil
            $0.status = .idle
        }
        moved.itemFrame.origin.x += 10
        await store.send(.hovered(moved)) { $0.hover = moved }
        await store.finish()
    }

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
    func onlyAppleMusicAndSpotifyGetMediaControls() {
        #expect(DockPreviewMediaPlayer(bundleIdentifier: "com.apple.Music") == .appleMusic)
        #expect(DockPreviewMediaPlayer(bundleIdentifier: "com.spotify.client") == .spotify)
        #expect(DockPreviewMediaPlayer(bundleIdentifier: "com.apple.TextEdit") == nil)
        #expect(DockPreviewMediaPlayer(bundleIdentifier: nil) == nil)
    }

    @Test
    func mediaAppWithoutWindowsShowsControlsOnlyPreview() async {
        let hover = DockHoverEvent(
            pid: 7, appName: "Spotify", itemFrame: .zero, screenFrame: .zero, mediaPlayer: .spotify
        )
        let store = TestStore(initialState: .init(
            isEnabled: true, authorization: .authorized, isObserving: true,
            hoverGeneration: 1, hover: hover, status: .loading
        )) { DockPreviewFeature() } withDependencies: {
            $0.dockPreview.isMediaPlaying = { _ in true }
        }

        await store.send(.windowsLoaded(generation: 1, hover: hover, result: .success([]))) {
            $0.preview = .init(generation: 1, appName: "Spotify", itemFrame: .zero,
                               screenFrame: .zero, windows: [], mediaPlayer: .spotify)
            $0.status = .idle
        }
        await store.receive(\.mediaPlaybackLoaded) {
            $0.preview?.isMediaPlaying = true
        }
        await store.finish()
    }

    @Test
    func windowListingFailureKeepsMediaControlsAvailable() async {
        let hover = DockHoverEvent(
            pid: 7, appName: "Music", itemFrame: .zero, screenFrame: .zero, mediaPlayer: .appleMusic
        )
        let store = TestStore(initialState: .init(
            isEnabled: true, authorization: .authorized, isObserving: true,
            hoverGeneration: 1, hover: hover, status: .loading
        )) { DockPreviewFeature() }

        await store.send(.windowsLoaded(generation: 1, hover: hover, result: .failure(.windowListing))) {
            $0.preview = .init(generation: 1, appName: "Music", itemFrame: .zero,
                               screenFrame: .zero, windows: [], mediaPlayer: .appleMusic)
            $0.status = .captureFailed
        }
        await store.receive(\.mediaPlaybackLoaded)
        await store.finish()
    }

    @Test
    func playPauseTogglesImmediatelyThenSyncsWithThePlayer() async {
        let commands = LockIsolated<[DockPreviewMediaCommand]>([])
        let store = TestStore(initialState: .init(
            isEnabled: true, authorization: .authorized, isObserving: true, hoverGeneration: 1,
            preview: .init(generation: 1, appName: "Music", itemFrame: .zero,
                           screenFrame: .zero, windows: [], mediaPlayer: .appleMusic)
        )) { DockPreviewFeature() } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.dockPreview.sendMediaCommand = { player, command in
                #expect(player == .appleMusic)
                commands.withValue { $0.append(command) }
            }
            $0.dockPreview.isMediaPlaying = { _ in false }
        }

        await store.send(.mediaCommandTapped(.playPause)) {
            $0.preview?.isMediaPlaying = true
        }
        // The player refused to start, so the button falls back to its real state.
        await store.receive(\.mediaPlaybackLoaded) {
            $0.preview?.isMediaPlaying = false
        }
        #expect(commands.value == [.playPause])
        await store.finish()
    }

    @Test
    func trackSkipsSendCommandsWithoutTogglingPlayback() async {
        let commands = LockIsolated<[DockPreviewMediaCommand]>([])
        let store = TestStore(initialState: .init(
            isEnabled: true, authorization: .authorized, isObserving: true, hoverGeneration: 1,
            preview: .init(generation: 1, appName: "Spotify", itemFrame: .zero, screenFrame: .zero,
                           windows: [], mediaPlayer: .spotify, isMediaPlaying: true)
        )) { DockPreviewFeature() } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.dockPreview.sendMediaCommand = { _, command in commands.withValue { $0.append(command) } }
            $0.dockPreview.isMediaPlaying = { _ in true }
        }

        await store.send(.mediaCommandTapped(.previousTrack))
        await store.receive(\.mediaPlaybackLoaded)
        await store.send(.mediaCommandTapped(.nextTrack))
        await store.receive(\.mediaPlaybackLoaded)
        #expect(commands.value == [.previousTrack, .nextTrack])
        await store.finish()
    }

    @Test
    func mediaCommandsAreIgnoredForOtherApps() async {
        let store = TestStore(initialState: .init(
            isEnabled: true, authorization: .authorized, isObserving: true, hoverGeneration: 1,
            preview: .init(generation: 1, appName: "TextEdit", itemFrame: .zero, screenFrame: .zero,
                           windows: [.init(id: 1, title: "Doc", pid: 42, frame: .zero, isActivatable: true)])
        )) { DockPreviewFeature() } withDependencies: {
            $0.dockPreview.sendMediaCommand = { _, _ in Issue.record("Unexpected media command") }
        }

        await store.send(.mediaCommandTapped(.playPause))
        await store.finish()
    }

    @Test
    func playbackStateFromAnOlderPreviewIsDiscarded() async {
        let store = TestStore(initialState: .init(
            isEnabled: true, authorization: .authorized, isObserving: true, hoverGeneration: 2,
            preview: .init(generation: 2, appName: "Music", itemFrame: .zero,
                           screenFrame: .zero, windows: [], mediaPlayer: .appleMusic)
        )) { DockPreviewFeature() }

        await store.send(.mediaPlaybackLoaded(generation: 1, isPlaying: true))
        #expect(store.state.preview?.isMediaPlaying == false)
    }

    @Test
    func mediaControlsAddRoomBelowThePreview() {
        let base = DockPreviewFeature.State.Preview(
            generation: 1, appName: "Music", itemFrame: .zero, screenFrame: .zero, windows: []
        )
        var controlsOnly = base
        controlsOnly.mediaPlayer = .appleMusic
        #expect(DockPreviewPanelController.size(for: controlsOnly, status: .idle) == CGSize(width: 240, height: 52))

        var withWindow = controlsOnly
        withWindow.windows = [.init(id: 1, title: "Music", pid: 7, frame: .zero, isActivatable: true)]
        #expect(DockPreviewPanelController.size(for: withWindow, status: .idle) == CGSize(width: 214, height: 204))

        var plainWindow = base
        plainWindow.windows = withWindow.windows
        #expect(DockPreviewPanelController.size(for: plainWindow, status: .idle) == CGSize(width: 214, height: 164))
        #expect(DockPreviewPanelController.size(for: base, status: .captureFailed) == CGSize(width: 240, height: 52))
        #expect(DockPreviewPanelController.size(for: controlsOnly, status: .captureFailed) == CGSize(width: 240, height: 92))
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

    @Test
    func autoHiddenBottomDockUsesTheCurrentVisibleScreenBoundary() {
        let item = CGRect(x: 500, y: 16, width: 64, height: 16)
        let visibleScreenAfterDockAppears = CGRect(x: 0, y: 88, width: 1_440, height: 812)
        let visibleScreen = DockPreviewPanelController.resolvedVisibleScreen(
            for: item,
            fallback: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            screens: [
                .init(
                    frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                    visibleFrame: visibleScreenAfterDockAppears
                )
            ]
        )

        let frame = DockPreviewPanelController.frame(
            size: CGSize(width: 240, height: 164),
            item: item,
            visibleScreen: visibleScreen
        )

        #expect(frame.minY == visibleScreenAfterDockAppears.minY)
        #expect(frame.maxY <= visibleScreenAfterDockAppears.maxY)
    }
}
