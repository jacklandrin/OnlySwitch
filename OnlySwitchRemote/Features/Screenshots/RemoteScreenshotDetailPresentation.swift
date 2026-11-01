import ComposableArchitecture
import RemoteCore
import SwiftUI

/// Presents the screenshot viewer from the app root. A sheet attached inside a page of the
/// root's paged `TabView` is dismissed by SwiftUI on its own (without writing the binding back),
/// which leaves `selectedItemID` set and makes later taps do nothing.
struct RemoteScreenshotDetailPresentation: ViewModifier {
    let store: StoreOf<RemoteScreenshotsFeature>

    func body(content: Content) -> some View {
        content
            .sheet(item: selectedItem) { _ in
                RemoteScreenshotDetailView(store: store)
            }
    }

    private var selectedItem: Binding<RemoteScreenshotItem?> {
        Binding(
            get: { store.selectedItemID.flatMap { store.state.item($0) } },
            set: { if $0 == nil, store.selectedItemID != nil { store.send(.detailDismissed) } }
        )
    }
}
