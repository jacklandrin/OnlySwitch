import ComposableArchitecture
import Testing
@testable import DesktopPet

@MainActor
struct DesktopPetPlaybackTests {
    @Test(arguments: [
        PlaybackSelectionCase(sources: [], expected: nil),
        PlaybackSelectionCase(sources: [.appleMusic], expected: .appleMusic),
        PlaybackSelectionCase(sources: [.spotify], expected: .spotify),
        PlaybackSelectionCase(sources: [.radio], expected: .radio),
        PlaybackSelectionCase(sources: [.appleMusic, .spotify], expected: .appleMusic),
        PlaybackSelectionCase(sources: [.appleMusic, .radio], expected: .appleMusic),
        PlaybackSelectionCase(sources: [.spotify, .radio], expected: .spotify),
        PlaybackSelectionCase(sources: [.appleMusic, .spotify, .radio], expected: .appleMusic)
    ])
    func refreshChoosesPlayingSourceByPriority(selection: PlaybackSelectionCase) async {
        let statuses = playing(selection.sources)
        let store = TestStore(initialState: DesktopPetPlaybackFeature.State()) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback.statuses = { statuses }
        }

        await store.send(.refresh) {
            $0.isEnabled = true
        }
        if let expected = selection.expected {
            await store.receive(.statusesUpdated(statuses)) {
                $0.source = expected
                $0.isPlaying = true
            }
        } else {
            await store.receive(.statusesUpdated(statuses))
        }
    }

    @Test func refreshPrefersPlayingSourceOverPausedSource() async {
        let store = TestStore(initialState: enabledState(source: .appleMusic, isPlaying: false)) {
            DesktopPetPlaybackFeature()
        }

        await store.send(.statusesUpdated([.appleMusic: .paused, .spotify: .playing])) {
            $0.source = .spotify
            $0.isPlaying = true
        }
    }

    @Test func refreshShowsPausedSourceWithPlayControl() async {
        let store = TestStore(initialState: enabledState(source: .spotify)) {
            DesktopPetPlaybackFeature()
        }

        await store.send(.statusesUpdated([.spotify: .paused])) {
            $0.isPlaying = false
        }
    }

    @Test func refreshKeepsDisplayedPausedSourceInsteadOfSwitching() async {
        let store = TestStore(initialState: enabledState(source: .spotify, isPlaying: false)) {
            DesktopPetPlaybackFeature()
        }

        await store.send(.statusesUpdated([.appleMusic: .paused, .spotify: .paused]))
    }

    @Test func refreshToleratesBriefGapDuringTrackChange() async {
        let store = TestStore(initialState: enabledState(source: .appleMusic)) {
            DesktopPetPlaybackFeature()
        }

        await store.send(.statusesUpdated([:])) {
            $0.missedRefreshCount = 1
        }
        await store.send(.statusesUpdated([.appleMusic: .playing])) {
            $0.missedRefreshCount = 0
        }
    }

    @Test func refreshHidesControlsWhenPlaybackStops() async {
        let store = TestStore(initialState: enabledState(source: .spotify)) {
            DesktopPetPlaybackFeature()
        }

        for count in 1...DesktopPetPlaybackFeature.missedRefreshLimit {
            await store.send(.statusesUpdated([:])) {
                $0.missedRefreshCount = count
            }
        }
        await store.send(.statusesUpdated([:])) {
            $0.source = nil
            $0.isPlaying = false
            $0.missedRefreshCount = 0
        }
    }

    @Test(arguments: DesktopPetPlaybackSource.allCases)
    func nextAdvancesDisplayedSource(source: DesktopPetPlaybackSource) async {
        let playback = PlaybackFixture(statuses: [source: .playing])
        let store = TestStore(initialState: enabledState(source: source)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.nextTapped)
        await store.receive(.statusesUpdated(playback.statuses))

        #expect(playback.commands == [.next(source)])
    }

    @Test func nextIsNotGatedOnATransientStatusRead() async {
        // Apple Music can briefly report no playing state, e.g. while it is in the background.
        let playback = PlaybackFixture(statuses: [:])
        let store = TestStore(initialState: enabledState(source: .appleMusic)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.nextTapped)
        await store.receive(.statusesUpdated([:])) {
            $0.missedRefreshCount = 1
        }

        #expect(playback.commands == [.next(.appleMusic)])
    }

    @Test func nextAdvancesPausedSource() async {
        let playback = PlaybackFixture(statuses: [.spotify: .paused])
        let store = TestStore(initialState: enabledState(source: .spotify, isPlaying: false)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.nextTapped)
        await store.receive(.statusesUpdated(playback.statuses))

        #expect(playback.commands == [.next(.spotify)])
    }

    @Test(arguments: DesktopPetPlaybackSource.allCases)
    func playPausePausesPlayingSource(source: DesktopPetPlaybackSource) async {
        let playback = PlaybackFixture(statuses: [source: .playing])
        playback.onCommand = { playback.statuses = source == .radio ? [:] : [source: .paused] }
        let store = TestStore(initialState: enabledState(source: source)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.playPauseTapped) {
            $0.isPlaying = false
            $0.pausedSource = source
        }
        await store.receive(.statusesUpdated(playback.statuses))

        #expect(playback.commands == [.pause(source)])
    }

    @Test func pausedRadioStaysAvailableToResume() async {
        let playback = PlaybackFixture(statuses: [.radio: .playing])
        playback.onCommand = {
            playback.statuses = playback.commands.last == .play(.radio) ? [.radio: .playing] : [:]
        }
        let store = TestStore(initialState: enabledState(source: .radio)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.playPauseTapped) {
            $0.isPlaying = false
            $0.pausedSource = .radio
        }
        await store.receive(.statusesUpdated([:]))
        await store.send(.playPauseTapped) {
            $0.isPlaying = true
            $0.pausedSource = nil
        }
        await store.receive(.statusesUpdated([.radio: .playing]))

        #expect(playback.commands == [.pause(.radio), .play(.radio)])
    }

    @Test func pausedSourceIsReplacedWhenAnotherSourcePlays() async {
        var state = enabledState(source: .radio, isPlaying: false)
        state.pausedSource = .radio
        let store = TestStore(initialState: state) {
            DesktopPetPlaybackFeature()
        }

        await store.send(.statusesUpdated([.spotify: .playing])) {
            $0.source = .spotify
            $0.isPlaying = true
            $0.pausedSource = nil
        }
    }

    @Test func playPauseResumesPausedSource() async {
        let playback = PlaybackFixture(statuses: [.appleMusic: .paused])
        playback.onCommand = { playback.statuses = [.appleMusic: .playing] }
        let store = TestStore(initialState: enabledState(source: .appleMusic, isPlaying: false)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.playPauseTapped) {
            $0.isPlaying = true
        }
        await store.receive(.statusesUpdated(playback.statuses))

        #expect(playback.commands == [.play(.appleMusic)])
    }

    @Test func commandsWithoutDisplayedSourceDoNothing() async {
        let playback = PlaybackFixture(statuses: [.radio: .playing])
        let store = TestStore(initialState: enabledState(source: nil)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.nextTapped)
        await store.send(.playPauseTapped)

        #expect(playback.commands.isEmpty)
        #expect(playback.statusReadCount == 0)
    }

    @Test func clearDisablesPlaybackAndIgnoresLateUpdates() async {
        var state = enabledState(source: .radio, isPlaying: false)
        state.pausedSource = .radio
        let playback = PlaybackFixture(statuses: [.radio: .playing])
        let store = TestStore(initialState: state) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.clear) {
            $0.source = nil
            $0.pausedSource = nil
            $0.isEnabled = false
        }
        await store.send(.statusesUpdated([.radio: .playing]))
        await store.send(.nextTapped)
        await store.send(.playPauseTapped)

        #expect(playback.commands.isEmpty)
        #expect(playback.statusReadCount == 0)
    }

    private func enabledState(
        source: DesktopPetPlaybackSource?,
        isPlaying: Bool = true
    ) -> DesktopPetPlaybackFeature.State {
        var state = DesktopPetPlaybackFeature.State()
        state.isEnabled = true
        state.source = source
        state.isPlaying = source != nil && isPlaying
        return state
    }

    private func playing(
        _ sources: Set<DesktopPetPlaybackSource>
    ) -> [DesktopPetPlaybackSource: DesktopPetPlaybackStatus] {
        Dictionary(uniqueKeysWithValues: sources.map { ($0, .playing) })
    }
}

struct PlaybackSelectionCase: Sendable {
    let sources: Set<DesktopPetPlaybackSource>
    let expected: DesktopPetPlaybackSource?
}

private enum PlaybackCommand: Equatable {
    case next(DesktopPetPlaybackSource)
    case play(DesktopPetPlaybackSource)
    case pause(DesktopPetPlaybackSource)
}

@MainActor
private final class PlaybackFixture {
    var statuses: [DesktopPetPlaybackSource: DesktopPetPlaybackStatus]
    var commands: [PlaybackCommand] = []
    var statusReadCount = 0
    var onCommand: () -> Void = {}

    init(statuses: [DesktopPetPlaybackSource: DesktopPetPlaybackStatus]) {
        self.statuses = statuses
    }

    var client: DesktopPetPlaybackClient {
        DesktopPetPlaybackClient(
            statuses: {
                self.statusReadCount += 1
                return self.statuses
            },
            next: { self.record(.next($0)) },
            play: { self.record(.play($0)) },
            pause: { self.record(.pause($0)) }
        )
    }

    private func record(_ command: PlaybackCommand) {
        commands.append(command)
        onCommand()
    }
}
