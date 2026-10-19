#if DEBUG
import ComposableArchitecture
import SwiftUI

struct RemoteDebugMenuView: View {
    let store: StoreOf<RemoteDebugMenuFeature>

    var body: some View {
        Form {
            Section {
                Toggle("Bypass Aphrodite Paywall", isOn: Binding(
                    get: { store.bypassAphroditePaywall },
                    set: { store.send(.bypassPaywallChanged($0)) }
                ))
            } header: {
                Text("Feature Flags")
            } footer: {
                Text("Show Aphrodite tools without an active subscription in Debug builds.")
            }
        }
        .navigationTitle("Debug Menu")
    }
}
#endif
