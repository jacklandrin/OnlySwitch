import ComposableArchitecture
import SwiftUI

struct RemoteAppShellView: View {
    @Bindable var store: StoreOf<RemoteAppShellFeature>

    var body: some View {
        RemoteAppView(store: store.scope(state: \.production, action: \.production))
            .safeAreaInset(edge: .bottom) {
                if store.production.requiredSettings?.isSetupRequired == true {
                    Button("Explore Demo", systemImage: "sparkles") {
                        store.send(.exploreDemoTapped)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("View sample Macs and remote controls without connecting to a Mac.")
                    .padding()
                }
            }
            .fullScreenCover(item: $store.scope(state: \.reviewDemo, action: \.reviewDemo)) { demoStore in
                ReviewDemoView(store: demoStore)
            }
    }
}
