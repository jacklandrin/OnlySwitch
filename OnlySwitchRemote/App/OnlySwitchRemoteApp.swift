import ComposableArchitecture
import SwiftUI

@main
struct OnlySwitchRemoteApp: App {
    let store = Store(initialState: RemoteAppFeature.State()) {
        RemoteAppFeature()
    }

    var body: some Scene {
        WindowGroup {
            RemoteAppView(store: store)
        }
    }
}
