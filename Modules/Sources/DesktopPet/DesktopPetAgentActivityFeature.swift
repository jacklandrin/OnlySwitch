import ComposableArchitecture
import Foundation

@Reducer
public struct DesktopPetAgentActivityFeature {
    /// A crashed or silent session loses its working indicator, without reporting success.
    static let activityLifetime: TimeInterval = 30 * 60

    public struct RunningTask: Equatable, Sendable {
        public var agent: DesktopPetAgent
        public var turnID: String?
        public var startedAt: Date
        public var lastActivity: Date
    }

    @ObservableState
    public struct State: Equatable {
        public var isEnabled = false
        public var runningTasks: [String: RunningTask] = [:]
        public var completion: DesktopPetAgentCompletion?
        var queuedCompletions: [DesktopPetAgentCompletion] = []
        var completedIDs: [String] = []
        var generation = 0

        public var runningAgents: [DesktopPetAgent] {
            DesktopPetAgent.allCases.filter { agent in runningTasks.values.contains { $0.agent == agent } }
        }

        public var showsStatus: Bool { completion != nil }

        public init() {}
    }

    public enum Action: Equatable, Sendable {
        case start
        case stop
        case updated(DesktopPetAgentUpdate, generation: Int)
        case dismissCompletion(id: String)
    }

    private enum CancelID { case monitor, completion }
    @Dependency(\.desktopPetAgentActivity) var activity
    @Dependency(\.continuousClock) var clock

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                guard !state.isEnabled else { return .none }
                state.isEnabled = true
                state.generation += 1
                return .run { [activity, generation = state.generation] send in
                    for await update in activity.updates() {
                        try Task.checkCancellation()
                        await send(.updated(update, generation: generation))
                    }
                }
                .cancellable(id: CancelID.monitor, cancelInFlight: true)

            case .stop:
                let nextGeneration = state.generation + 1
                state = State()
                state.generation = nextGeneration
                return .merge(.cancel(id: CancelID.monitor), .cancel(id: CancelID.completion))

            case let .updated(update, generation):
                guard state.isEnabled, generation == state.generation else { return .none }
                let previousCompletion = state.completion?.id
                for event in update.events {
                    apply(event, to: &state)
                }
                state.runningTasks = state.runningTasks.filter {
                    update.date.timeIntervalSince($0.value.lastActivity) <= Self.activityLifetime
                }
                return state.completion?.id != previousCompletion ? dismissLater(state.completion) : .none

            case let .dismissCompletion(id):
                guard state.isEnabled, state.completion?.id == id else { return .none }
                state.completion = state.queuedCompletions.isEmpty ? nil : state.queuedCompletions.removeFirst()
                return dismissLater(state.completion)
            }
        }
    }

    private func apply(_ event: DesktopPetAgentEvent, to state: inout State) {
        switch event.kind {
        case .started:
            if let running = state.runningTasks[event.sessionID], running.startedAt > event.date { return }
            state.runningTasks[event.sessionID] = RunningTask(
                agent: event.agent, turnID: event.turnID, startedAt: event.date, lastActivity: event.date
            )
        case .activity:
            if let lastActivity = state.runningTasks[event.sessionID]?.lastActivity {
                state.runningTasks[event.sessionID]?.lastActivity = max(lastActivity, event.date)
            }
        case .completed, .stopped:
            guard let running = state.runningTasks[event.sessionID],
                  event.date >= running.startedAt,
                  event.turnID == nil || running.turnID == nil || event.turnID == running.turnID else { return }
            state.runningTasks[event.sessionID] = nil
            guard event.kind == .completed, !event.isHistorical else { return }
            let id = "\(event.sessionID):\(event.id)"
            guard !state.completedIDs.contains(id) else { return }
            state.completedIDs.append(id)
            state.completedIDs = Array(state.completedIDs.suffix(256))
            let completion = DesktopPetAgentCompletion(id: id, agent: event.agent)
            if state.completion == nil {
                state.completion = completion
            } else if state.queuedCompletions.count < 32 {
                state.queuedCompletions.append(completion)
            }
        case .unavailable:
            state.runningTasks[event.sessionID] = nil
        }
    }

    private func dismissLater(_ completion: DesktopPetAgentCompletion?) -> Effect<Action> {
        guard let completion else { return .cancel(id: CancelID.completion) }
        return .run { [clock] send in
            try await clock.sleep(for: .seconds(8))
            await send(.dismissCompletion(id: completion.id))
        }
        .cancellable(id: CancelID.completion, cancelInFlight: true)
    }
}
