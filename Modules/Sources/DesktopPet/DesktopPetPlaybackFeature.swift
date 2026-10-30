import ComposableArchitecture

@Reducer
public struct DesktopPetPlaybackFeature {
    /// Empty refreshes tolerated before the controls hide. Players can briefly report no state,
    /// e.g. between tracks, and hiding would resize the panel under the cursor.
    static let missedRefreshLimit = 2

    @ObservableState
    public struct State: Equatable {
        public var source: DesktopPetPlaybackSource?
        public var isPlaying = false
        public var isEnabled = false
        public var nowPlaying: DesktopPetNowPlaying?
        /// Source paused from the pet. Kept available so players without a paused state
        /// (radio) can be resumed.
        var pausedSource: DesktopPetPlaybackSource?
        var missedRefreshCount = 0
        public init() {}
    }

    public enum Action: Equatable, Sendable {
        case refresh
        case statusesUpdated(
            [DesktopPetPlaybackSource: DesktopPetPlaybackStatus],
            nowPlaying: [DesktopPetPlaybackSource: DesktopPetNowPlaying] = [:]
        )
        case nextTapped
        case playPauseTapped
        case clear
    }

    private enum CancelID { case refresh, command }
    @Dependency(\.desktopPetPlayback) var playback

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .refresh:
                state.isEnabled = true
                return .run { [playback, pausedSource = state.pausedSource] send in
                    let update = await Self.update(from: playback, pausedSource: pausedSource)
                    try Task.checkCancellation()
                    await send(update)
                }
                .cancellable(id: CancelID.refresh, cancelInFlight: true)
            case let .statusesUpdated(statuses, nowPlaying):
                guard state.isEnabled else { return .none }
                var statuses = statuses
                if let pausedSource = state.pausedSource {
                    if statuses.values.contains(.playing) {
                        state.pausedSource = nil
                    } else if statuses[pausedSource] == nil {
                        statuses[pausedSource] = .paused
                    }
                }
                if state.source != nil,
                   statuses.isEmpty,
                   state.missedRefreshCount < Self.missedRefreshLimit {
                    state.missedRefreshCount += 1
                    return .none
                }
                state.missedRefreshCount = 0
                state.source = DesktopPetPlaybackSource.preferred(in: statuses, current: state.source)
                state.isPlaying = state.source.map { statuses[$0] == .playing } ?? false
                state.nowPlaying = state.source.flatMap { nowPlaying[$0] }
                return .none
            case .nextTapped:
                guard state.isEnabled, let source = state.source else { return .none }
                return command(pausedSource: state.pausedSource) { $0.next(source) }
            case .playPauseTapped:
                guard state.isEnabled, let source = state.source else { return .none }
                let wasPlaying = state.isPlaying
                state.isPlaying = !wasPlaying
                state.pausedSource = wasPlaying ? source : nil
                return command(pausedSource: state.pausedSource) {
                    wasPlaying ? $0.pause(source) : $0.play(source)
                }
            case .clear:
                state.isEnabled = false
                state.source = nil
                state.isPlaying = false
                state.pausedSource = nil
                state.nowPlaying = nil
                state.missedRefreshCount = 0
                return .merge(.cancel(id: CancelID.refresh), .cancel(id: CancelID.command))
            }
        }
    }

    /// Sends a command to the displayed source without re-checking its status first: a stale
    /// "not playing" read must not swallow the tap. The live client guards against launching apps.
    private func command(
        pausedSource: DesktopPetPlaybackSource?,
        _ perform: @escaping @MainActor @Sendable (DesktopPetPlaybackClient) -> Void
    ) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.refresh),
            .run { [playback] send in
                let update = await MainActor.run { () -> Action? in
                    guard !Task.isCancelled else { return nil }
                    perform(playback)
                    return Self.update(from: playback, pausedSource: pausedSource)
                }
                try Task.checkCancellation()
                guard let update else { return }
                await send(update)
            }
            .cancellable(id: CancelID.command, cancelInFlight: true)
        )
    }

    /// Reads now-playing text only for sources that can be displayed, so polling does not
    /// query players that are not active. A paused source is kept displayable by the reducer.
    @MainActor
    private static func update(
        from playback: DesktopPetPlaybackClient,
        pausedSource: DesktopPetPlaybackSource?
    ) -> Action {
        let statuses = playback.statuses()
        var nowPlaying: [DesktopPetPlaybackSource: DesktopPetNowPlaying] = [:]
        for source in DesktopPetPlaybackSource.allCases
        where statuses[source] != nil || source == pausedSource {
            nowPlaying[source] = playback.nowPlaying(source)
        }
        return .statusesUpdated(statuses, nowPlaying: nowPlaying)
    }
}
