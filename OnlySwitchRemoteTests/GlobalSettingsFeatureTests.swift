import ComposableArchitecture
import Testing
@testable import OnlySwitchRemote

@MainActor
struct GlobalSettingsMembershipTests {
    @Test func membershipEmitsDelegateWithoutChangingRequiredSetup() async {
        let store = TestStore(initialState: GlobalSettingsFeature.State(isSetupRequired: true)) { GlobalSettingsFeature() }
        let originalState = store.state
        await store.send(.membershipTapped)
        await store.receive(.delegate(.openMembership))
        #expect(store.state == originalState)
    }
}
