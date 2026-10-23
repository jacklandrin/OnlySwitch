import ComposableArchitecture

@Reducer
public struct DesktopPetPlaybackFeature {
    @ObservableState
    public struct State: Equatable {
        public var source: DesktopPetPlaybackSource?
        public var isEnabled = false
        public init() {}
    }

    public enum Action: Equatable {
        case refresh
        case sourcesUpdated(Set<DesktopPetPlaybackSource>)
        case nextTapped
        case clear
    }

    private enum CancelID { case refresh, next }
    @Dependency(\.desktopPetPlayback) var playback

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .refresh:
                state.isEnabled = true
                return .run { [playback] send in
                    let sources = await playback.playingSources()
                    try Task.checkCancellation()
                    await send(.sourcesUpdated(sources))
                }
                .cancellable(id: CancelID.refresh, cancelInFlight: true)
            case let .sourcesUpdated(sources):
                guard state.isEnabled else { return .none }
                state.source = DesktopPetPlaybackSource.preferred(in: sources)
                return .none
            case .nextTapped:
                guard state.isEnabled, let source = state.source else { return .none }
                return .run { [playback] send in
                    let sources = await MainActor.run {
                        guard !Task.isCancelled else { return Set<DesktopPetPlaybackSource>() }
                        if playback.playingSources().contains(source) {
                            playback.next(source)
                        }
                        return playback.playingSources()
                    }
                    try Task.checkCancellation()
                    await send(.sourcesUpdated(sources))
                }
                .cancellable(id: CancelID.next, cancelInFlight: true)
            case .clear:
                state.isEnabled = false
                state.source = nil
                return .merge(.cancel(id: CancelID.refresh), .cancel(id: CancelID.next))
            }
        }
    }
}
