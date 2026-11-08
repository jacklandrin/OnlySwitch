import ComposableArchitecture
import Foundation
import RemoteCore

@Reducer
struct RemoteSystemMonitorConfigurationFeature {
    @ObservableState
    struct State: Equatable {
        var layout: MacSystemMonitorLayout
        var isSaveFailed = false
    }

    enum SaveResult: Equatable, Sendable {
        case success
        case failure
    }

    enum Action: Equatable {
        case setVisible(SystemMonitorMetric, Bool)
        case move(IndexSet, Int)
        case retrySave
        case saveResponse(SaveResult)
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case layoutChanged(MacSystemMonitorLayout)
    }

    @Dependency(\.remotePersistence) private var persistence
    private enum CancelID { case save }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setVisible(metric, isVisible):
                state.layout.setVisible(metric, isVisible: isVisible)
                state.isSaveFailed = false
                return changed(state.layout)

            case let .move(source, destination):
                state.layout.move(from: source, to: destination)
                state.isSaveFailed = false
                return changed(state.layout)

            case .retrySave:
                state.isSaveFailed = false
                return save(state.layout)

            case .saveResponse(.success):
                state.isSaveFailed = false
                return .none

            case .saveResponse(.failure):
                state.isSaveFailed = true
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func changed(_ layout: MacSystemMonitorLayout) -> Effect<Action> {
        .concatenate(.send(.delegate(.layoutChanged(layout))), save(layout))
    }

    private func save(_ layout: MacSystemMonitorLayout) -> Effect<Action> {
        .run { [persistence] send in
            do {
                try await persistence.saveSystemMonitorLayout(layout)
                await send(.saveResponse(.success))
            } catch {
                await send(.saveResponse(.failure))
            }
        }
        .cancellable(id: CancelID.save, cancelInFlight: true)
    }
}
