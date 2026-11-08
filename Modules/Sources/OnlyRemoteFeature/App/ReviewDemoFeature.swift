import ComposableArchitecture
import Foundation

@Reducer
struct ReviewDemoFeature {
    @ObservableState
    struct State: Equatable {
        var app: RemoteAppFeature.State

        init(app: RemoteAppFeature.State = .init(
            hasCompletedInitialSetup: true,
            persistenceWriterID: UUID(uuidString: "00000000-0000-0000-0000-00000000D020")!
        )) {
            self.app = app
        }
    }

    enum Action: Equatable {
        case app(RemoteAppFeature.Action)
        case exitTapped
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.app, action: \.app) { RemoteAppFeature() }
        Reduce { _, _ in .none }
    }
}
