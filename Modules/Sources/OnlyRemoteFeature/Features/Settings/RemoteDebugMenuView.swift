#if DEBUG
import ComposableArchitecture
import SwiftUI

struct RemoteDebugMenuView: View {
    let store: StoreOf<RemoteDebugMenuFeature>

    var body: some View {
        Form {
            Section {
                Toggle("Bypass OnlyRemote Plus Paywall", isOn: Binding(
                    get: { store.bypassPlusPaywall },
                    set: { store.send(.bypassPaywallChanged($0)) }
                ))
            } header: {
                Text("Feature Flags")
            } footer: {
                Text("Show OnlyRemote Plus tabs without an active subscription in Debug builds.")
            }
        }
        .navigationTitle("Debug Menu")
    }
}
#endif
