import ComposableArchitecture
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteAppSmokeTests {
    @Test func initialStateRequiresSetupWithoutPairedMacs() {
        let state = RemoteAppFeature.State(hasCompletedInitialSetup: false)
        #expect(state.requiresSetup)
        #expect(state.path.isEmpty)
        #expect(state.requiredSettings != nil)
    }
}
