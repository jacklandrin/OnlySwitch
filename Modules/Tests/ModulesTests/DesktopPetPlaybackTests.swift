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
        let sources = selection.sources
        let store = TestStore(initialState: DesktopPetPlaybackFeature.State()) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback.playingSources = { sources }
        }

        await store.send(.refresh) {
            $0.isEnabled = true
        }
        if let expected = selection.expected {
            await store.receive(.sourcesUpdated(sources)) {
                $0.source = expected
            }
        } else {
            await store.receive(.sourcesUpdated(sources))
        }
    }

    @Test func refreshHidesButtonWhenPlaybackStops() async {
        let store = TestStore(initialState: enabledState(source: .spotify)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback.playingSources = { [] }
        }

        await store.send(.refresh)
        await store.receive(.sourcesUpdated([])) {
            $0.source = nil
        }
    }

    @Test(arguments: DesktopPetPlaybackSource.allCases)
    func nextAdvancesOnlyTheDisplayedPlayingSource(source: DesktopPetPlaybackSource) async {
        let playback = PlaybackFixture(sources: Set(DesktopPetPlaybackSource.allCases))
        let store = TestStore(initialState: enabledState(source: source)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.nextTapped)
        if source == .appleMusic {
            await store.receive(.sourcesUpdated(playback.sources))
        } else {
            await store.receive(.sourcesUpdated(playback.sources)) {
                $0.source = .appleMusic
            }
        }

        #expect(playback.advancedSources == [source])
    }

    @Test(arguments: [Set<DesktopPetPlaybackSource>(), [.spotify, .radio]])
    func staleButtonDoesNotAdvanceAnotherSource(sources: Set<DesktopPetPlaybackSource>) async {
        let playback = PlaybackFixture(sources: sources)
        let store = TestStore(initialState: enabledState(source: .appleMusic)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.nextTapped)
        await store.receive(.sourcesUpdated(sources)) {
            $0.source = sources.isEmpty ? nil : .spotify
        }

        #expect(playback.advancedSources.isEmpty)
    }

    @Test func nextWithoutDisplayedSourceDoesNothing() async {
        let playback = PlaybackFixture(sources: [.radio])
        let store = TestStore(initialState: enabledState(source: nil)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.nextTapped)

        #expect(playback.advancedSources.isEmpty)
        #expect(playback.sourceReadCount == 0)
    }

    @Test func clearDisablesPlaybackAndIgnoresLateUpdates() async {
        let playback = PlaybackFixture(sources: [.radio])
        let store = TestStore(initialState: enabledState(source: .radio)) {
            DesktopPetPlaybackFeature()
        } withDependencies: {
            $0.desktopPetPlayback = playback.client
        }

        await store.send(.clear) {
            $0.source = nil
            $0.isEnabled = false
        }
        await store.send(.sourcesUpdated([.radio]))
        await store.send(.nextTapped)

        #expect(playback.advancedSources.isEmpty)
        #expect(playback.sourceReadCount == 0)
    }

    private func enabledState(source: DesktopPetPlaybackSource?) -> DesktopPetPlaybackFeature.State {
        var state = DesktopPetPlaybackFeature.State()
        state.isEnabled = true
        state.source = source
        return state
    }
}

struct PlaybackSelectionCase: Sendable {
    let sources: Set<DesktopPetPlaybackSource>
    let expected: DesktopPetPlaybackSource?
}

@MainActor
private final class PlaybackFixture {
    var sources: Set<DesktopPetPlaybackSource>
    var advancedSources: [DesktopPetPlaybackSource] = []
    var sourceReadCount = 0

    init(sources: Set<DesktopPetPlaybackSource>) {
        self.sources = sources
    }

    var client: DesktopPetPlaybackClient {
        DesktopPetPlaybackClient(
            playingSources: {
                self.sourceReadCount += 1
                return self.sources
            },
            next: { self.advancedSources.append($0) }
        )
    }
}
