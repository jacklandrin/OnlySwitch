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

    @Test func refreshShowsNowPlayingForDisplayedSource() async {
        let song = DesktopPetNowPlaying(title: "Song", subtitle: "Artist")
        let station = DesktopPetNowPlaying(title: "Station")
        let playback = PlaybackFixture(statuses: [.spotify: .playing, .radio: .playing])
        playback.nowPlaying = [.spotify: song, .radio: station]
        let store = TestStore(initialState: DesktopPetPlaybackFeature.State()) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.refresh) {
            $0.isEnabled = true
        }
        await store.receive(.statusesUpdated(playback.statuses, nowPlaying: playback.nowPlaying)) {
            $0.source = .spotify
            $0.isPlaying = true
            $0.nowPlaying = song
        }
    }

    @Test func nowPlayingFollowsTrackChanges() async {
        var state = enabledState(source: .appleMusic)
        state.nowPlaying = DesktopPetNowPlaying(title: "Old", subtitle: "Artist")
        let store = TestStore(initialState: state) {
            DesktopPetPlaybackFeature()
        }
        let next = DesktopPetNowPlaying(title: "New", subtitle: "Artist")

        await store.send(.statusesUpdated([.appleMusic: .playing], nowPlaying: [.appleMusic: next])) {
            $0.nowPlaying = next
        }
        await store.send(.statusesUpdated([.appleMusic: .playing])) {
            $0.nowPlaying = nil
        }
    }

    @Test func briefGapKeepsNowPlaying() async {
        var state = enabledState(source: .appleMusic)
        state.nowPlaying = DesktopPetNowPlaying(title: "Song", subtitle: "Artist")
        let store = TestStore(initialState: state) {
            DesktopPetPlaybackFeature()
        }

        await store.send(.statusesUpdated([:])) {
            $0.missedRefreshCount = 1
        }
    }

    @Test func pausedRadioKeepsStationInfo() async {
        let station = DesktopPetNowPlaying(title: "Station")
        let playback = PlaybackFixture(statuses: [.radio: .playing])
        playback.nowPlaying = [.radio: station]
        playback.onCommand = { playback.statuses = [:] }
        var state = enabledState(source: .radio)
        state.nowPlaying = station
        let store = TestStore(initialState: state) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.playPauseTapped) {
            $0.isPlaying = false
            $0.pausedSource = .radio
        }
        await store.receive(.statusesUpdated([:], nowPlaying: [.radio: station]))
    }

    @Test func clearRemovesNowPlaying() async {
        var state = enabledState(source: .spotify)
        state.nowPlaying = DesktopPetNowPlaying(title: "Song", subtitle: "Artist")
        let store = TestStore(initialState: state) {
            DesktopPetPlaybackFeature()
        }

        await store.send(.clear) {
            $0.source = nil
            $0.isPlaying = false
            $0.isEnabled = false
            $0.nowPlaying = nil
        }
    }

    @Test func nowPlayingIsOnlyReadForSourcesWithStatus() async {
        let playback = PlaybackFixture(statuses: [.spotify: .playing])
        let store = TestStore(initialState: DesktopPetPlaybackFeature.State()) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.refresh) {
            $0.isEnabled = true
        }
        await store.receive(.statusesUpdated(playback.statuses)) {
            $0.source = .spotify
            $0.isPlaying = true
        }

        #expect(playback.nowPlayingReads == [.spotify])
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
    var nowPlaying: [DesktopPetPlaybackSource: DesktopPetNowPlaying] = [:]
    var statusReadCount = 0
    var nowPlayingReads: [DesktopPetPlaybackSource] = []
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
            nowPlaying: {
                self.nowPlayingReads.append($0)
                return self.nowPlaying[$0]
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

struct DesktopPetNowPlayingTests {
    @Test func trackShowsNameAndArtist() {
        #expect(
            DesktopPetNowPlaying.track(name: " Song ", artist: "Artist\n")
                == DesktopPetNowPlaying(title: "Song", subtitle: "Artist")
        )
    }

    @Test func trackWithoutArtistOmitsSubtitle() {
        #expect(
            DesktopPetNowPlaying.track(name: "Song", artist: " ")
                == DesktopPetNowPlaying(title: "Song")
        )
        #expect(
            DesktopPetNowPlaying.track(name: "Song", artist: nil)
                == DesktopPetNowPlaying(title: "Song")
        )
    }

    @Test(arguments: [nil, "", "  "])
    func trackWithoutNameIsHidden(name: String?) {
        #expect(DesktopPetNowPlaying.track(name: name, artist: "Artist") == nil)
    }

    @Test func radioPrefersStreamInfo() {
        #expect(
            DesktopPetNowPlaying.radio(stationName: "Station", streamInfo: "Artist - Song")
                == DesktopPetNowPlaying(title: "Artist - Song")
        )
    }

    @Test(arguments: ["", " \n"])
    func radioFallsBackToStationName(streamInfo: String) {
        #expect(
            DesktopPetNowPlaying.radio(stationName: "Station", streamInfo: streamInfo)
                == DesktopPetNowPlaying(title: "Station")
        )
    }

    @Test func radioWithoutAnyTextIsHidden() {
        #expect(DesktopPetNowPlaying.radio(stationName: "", streamInfo: "") == nil)
    }
}

struct DesktopPetNowPlayingLineTests {
    @Test func shortTextStaysStill() {
        #expect(!DesktopPetNowPlayingLine.title.scrolls("Song", reduceMotion: false))
    }

    @Test(arguments: [DesktopPetNowPlayingLine.title, .subtitle])
    func overflowingTextScrolls(line: DesktopPetNowPlayingLine) {
        let text = "A very long stream title that cannot fit above the pet"
        #expect(line.scrolls(text, reduceMotion: false))
    }

    @Test func reducedMotionTruncatesInsteadOfScrolling() {
        let text = "A very long stream title that cannot fit above the pet"
        #expect(!DesktopPetNowPlayingLine.title.scrolls(text, reduceMotion: true))
    }
}
