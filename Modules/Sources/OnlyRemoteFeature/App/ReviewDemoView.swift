import ComposableArchitecture
import SwiftUI

struct ReviewDemoView: View {
    let store: StoreOf<ReviewDemoFeature>

    var body: some View {
        RemoteAppView(store: store.scope(state: \.app, action: \.app))
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    Label("Demo Mode — sample Macs and controls", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Exit Demo") { store.send(.exitTapped) }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Returns to normal Mac pairing")
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
    }
}
