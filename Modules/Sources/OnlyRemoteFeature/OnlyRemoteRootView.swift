import ComposableArchitecture
import SwiftUI

/// The OnlyRemote app's root content; the app target only hosts it in a WindowGroup.
public struct OnlyRemoteRootView: View {
    /// One root store for the process lifetime, matching the former `let store` on the `App` struct.
    /// A static is used instead of `@State` so re-creating this view value never builds a throwaway store.
    @MainActor private static let store = Store(initialState: RemoteAppShellFeature.State(
        production: .init(
            hasCompletedInitialSetup: RemotePersistenceClient.initialSetupSeed()
        )
    )) {
        RemoteAppShellFeature()
    }

    public init() {}

    public var body: some View {
        RemoteAppShellView(store: Self.store)
    }
}
