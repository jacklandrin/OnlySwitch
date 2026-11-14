import ComposableArchitecture
import Foundation

/// Owns the pet's hunger and its short feed/pet reactions. Hunger is recomputed from the wall
/// clock on every check, so the 60-second loop only decides how quickly a change appears.
@Reducer
public struct DesktopPetNeedsFeature {
    public static let reactionDuration: Duration = .seconds(3)
    public static let checkInterval: Duration = .seconds(60)

    @ObservableState
    public struct State: Equatable {
        public var needs: DesktopPetNeeds?
        public var isHungerEnabled = true
        public var isHungry = false
        public var reaction: DesktopPetReaction?
        public var reactionStartedAt: Date?

        public init() {}
    }

    public enum Action: Equatable {
        case start
        case stop
        case tick
        case settingsChanged
        case feedTapped
        case petTapped
        case reactionFinished
    }

    enum CancelID { case hungerLoop, reaction }

    @Dependency(\.desktopPetNeedsStorage) var storage
    @Dependency(\.date) var date
    @Dependency(\.continuousClock) var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                let now = date.now
                let loaded = storage.loadNeeds()
                let needs = (loaded ?? DesktopPetNeeds(lastFedAt: now)).normalized(at: now)
                state.needs = needs
                refresh(&state, now: now)
                let save: Effect<Action> = loaded == needs
                    ? .none
                    : .run { [storage] _ in storage.saveNeeds(needs) }
                let loop: Effect<Action> = .run { [clock] send in
                    while true {
                        try await clock.sleep(for: Self.checkInterval)
                        await send(.tick)
                    }
                }
                .cancellable(id: CancelID.hungerLoop, cancelInFlight: true)
                return .merge(save, loop)

            case .stop:
                state.reaction = nil
                state.reactionStartedAt = nil
                return .merge(.cancel(id: CancelID.hungerLoop), .cancel(id: CancelID.reaction))

            case .tick, .settingsChanged:
                refresh(&state, now: date.now)
                return .none

            case .feedTapped:
                guard state.isHungerEnabled else { return .none }
                let now = date.now
                var needs = state.needs ?? DesktopPetNeeds(lastFedAt: now)
                needs.feed(at: now)
                state.needs = needs
                state.isHungry = false
                let fedNeeds = needs
                return .merge(
                    .run { [storage] _ in storage.saveNeeds(fedNeeds) },
                    startReaction(.eating, state: &state, now: now)
                )

            case .petTapped:
                return startReaction(.petted, state: &state, now: date.now)

            case .reactionFinished:
                state.reaction = nil
                state.reactionStartedAt = nil
                return .none
            }
        }
    }

    private func refresh(_ state: inout State, now: Date) {
        state.isHungerEnabled = storage.isHungerEnabled()
        state.isHungry = state.isHungerEnabled && (state.needs?.isHungry(at: now) ?? false)
    }

    private func startReaction(_ reaction: DesktopPetReaction, state: inout State, now: Date) -> Effect<Action> {
        state.reaction = reaction
        state.reactionStartedAt = now
        return .run { [clock] send in
            try await clock.sleep(for: Self.reactionDuration)
            await send(.reactionFinished)
        }
        .cancellable(id: CancelID.reaction, cancelInFlight: true)
    }
}
