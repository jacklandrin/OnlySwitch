import ComposableArchitecture
import SwiftUI

struct RemoteAphroditeAccessView: View {
    let accessStore: StoreOf<RemoteAphroditeAccessFeature>
    let toolsStore: StoreOf<RemoteAphroditeFeature>

    var body: some View {
        Group {
            if accessStore.canAccess {
                RemoteAphroditeView(store: toolsStore)
            } else {
                RemotePaywallView(
                    store: accessStore.scope(state: \.paywall, action: \.paywall),
                    presentation: .inline
                )
                .safeAreaPadding(.bottom, 76)
            }
        }
    }
}
