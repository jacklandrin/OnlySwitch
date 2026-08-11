import ComposableArchitecture
import SwiftUI

@main
struct OnlySwitchRemoteApp: App {
    let store = Store(initialState: RemoteAppShellFeature.State(
        production: .init(
            hasCompletedInitialSetup: RemotePersistenceClient.initialSetupSeed()
        )
    )) {
        RemoteAppShellFeature()
    }

    var body: some Scene {
        WindowGroup {
            RemoteAppShellView(store: store)
        }
    }
}
