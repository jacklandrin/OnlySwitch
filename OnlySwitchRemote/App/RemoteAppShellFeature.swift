import ComposableArchitecture

@Reducer
struct RemoteAppShellFeature {
    @ObservableState
    struct State: Equatable {
        var production: RemoteAppFeature.State
        @Presents var reviewDemo: ReviewDemoFeature.State?

        init(production: RemoteAppFeature.State) {
            self.production = production
        }
    }

    enum Action: Equatable {
        case production(RemoteAppFeature.Action)
        case exploreDemoTapped
        case reviewDemoReady
        case reviewDemo(PresentationAction<ReviewDemoFeature.Action>)
    }

    private enum CancelID { case prepareReviewDemo }

    private let runtime: RemoteReviewDemoRuntime

    init(runtime: RemoteReviewDemoRuntime = .init()) {
        self.runtime = runtime
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.production, action: \.production) { RemoteAppFeature() }
        Reduce { state, action in
            switch action {
            case .exploreDemoTapped:
                state.reviewDemo = nil
                return .run { [runtime] send in
                    await runtime.reset()
                    await send(.reviewDemoReady)
                }
                .cancellable(id: CancelID.prepareReviewDemo, cancelInFlight: true)

            case .reviewDemoReady:
                state.reviewDemo = .init()
                return .none

            case .reviewDemo(.presented(.exitTapped)):
                state.reviewDemo = nil
                return .run { _ in await runtime.reset() }

            case .production, .reviewDemo:
                return .none
            }
        }
        .ifLet(\.$reviewDemo, action: \.reviewDemo) {
            ReviewDemoFeature()
                .dependency(\.remoteConnection, .reviewDemo(runtime: runtime))
                .dependency(\.remotePersistence, .reviewDemo(runtime: runtime))
        }
    }
}
