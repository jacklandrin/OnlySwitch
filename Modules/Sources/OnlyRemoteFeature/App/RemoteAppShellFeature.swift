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
    /// The demo's own screenshot cache and image loader, so the demo never reads or writes the real
    /// `Caches/OnlyRemote/Screenshots` folder or loads originals over the live connection.
    private let screenshotCache: RemoteScreenshotCacheClient
    private let screenshotImages: RemoteScreenshotImageClient

    init(runtime: RemoteReviewDemoRuntime = .init(), screenshotCache: RemoteScreenshotCacheClient = .reviewDemo) {
        self.runtime = runtime
        self.screenshotCache = screenshotCache
        self.screenshotImages = .reviewDemo(connection: .reviewDemo(runtime: runtime), cache: screenshotCache)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.production, action: \.production) { RemoteAppFeature() }
        Reduce { state, action in
            switch action {
            case .exploreDemoTapped:
                state.reviewDemo = nil
                return .run { [runtime, screenshotCache] send in
                    await Self.resetDemo(runtime: runtime, screenshotCache: screenshotCache)
                    await send(.reviewDemoReady)
                }
                .cancellable(id: CancelID.prepareReviewDemo, cancelInFlight: true)

            case .reviewDemoReady:
                state.reviewDemo = .init()
                return .none

            case .reviewDemo(.presented(.exitTapped)):
                state.reviewDemo = nil
                return .run { [runtime, screenshotCache] _ in
                    await Self.resetDemo(runtime: runtime, screenshotCache: screenshotCache)
                }

            case .production, .reviewDemo:
                return .none
            }
        }
        .ifLet(\.$reviewDemo, action: \.reviewDemo) {
            ReviewDemoFeature()
                .dependency(\.remoteConnection, .reviewDemo(runtime: runtime))
                .dependency(\.remotePersistence, .reviewDemo(runtime: runtime))
                .dependency(\.remoteScreenshotCache, screenshotCache)
                .dependency(\.remoteScreenshotImages, screenshotImages)
        }
    }

    private static func resetDemo(runtime: RemoteReviewDemoRuntime, screenshotCache: RemoteScreenshotCacheClient) async {
        await runtime.reset()
        await screenshotCache.removeMac(RemoteReviewDemoRuntime.studioMacID)
        await screenshotCache.removeMac(RemoteReviewDemoRuntime.travelMacID)
    }
}
