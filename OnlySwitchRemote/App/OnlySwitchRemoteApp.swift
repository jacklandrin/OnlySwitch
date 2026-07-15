import ComposableArchitecture
import SwiftUI

@main
struct OnlySwitchRemoteApp: App {
    let store = Store(initialState: RemoteAppFeature.State(
        hasCompletedInitialSetup: RemotePersistenceClient.initialSetupSeed()
    )) {
        RemoteAppFeature()
    }

    var body: some Scene {
        WindowGroup {
            RemoteAppView(store: store)
        }
    }
}
