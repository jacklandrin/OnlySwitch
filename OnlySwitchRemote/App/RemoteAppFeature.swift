import ComposableArchitecture
import Foundation

@Reducer
struct RemoteAppFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<Path.State>()
        var pairedMacIDs: [UUID] = []

        var requiresSetup: Bool {
            pairedMacIDs.isEmpty
        }

        init() {
            path.append(.setup(.init()))
        }
    }

    enum Action {
        case path(StackActionOf<Path>)
    }

    @Reducer
    enum Path {
        case setup(SetupFeature)
    }

    var body: some ReducerOf<Self> {
        Reduce { _, _ in .none }
            .forEach(\.path, action: \.path)
    }
}

@Reducer
struct SetupFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

extension RemoteAppFeature.Path.State: Equatable {}
