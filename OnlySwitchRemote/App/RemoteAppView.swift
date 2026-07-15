import ComposableArchitecture
import SwiftUI

struct RemoteAppView: View {
    @Bindable var store: StoreOf<RemoteAppFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            EmptyView()
        } destination: { store in
            switch store.case {
            case .setup:
                Text("Settings")
            }
        }
    }
}
