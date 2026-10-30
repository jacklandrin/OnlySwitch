import ComposableArchitecture
import SwiftUI

struct RemotePlusGateView<Content: View>: View {
    let accessStore: StoreOf<RemotePlusAccessFeature>
    @ViewBuilder let content: () -> Content

    var body: some View {
        if accessStore.canAccess {
            content()
        } else {
            RemotePaywallView(
                store: accessStore.scope(state: \.paywall, action: \.paywall),
                presentation: .inline
            )
            .safeAreaPadding(.bottom, 76)
        }
    }
}
