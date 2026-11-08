import ComposableArchitecture
import RemoteCore
import SwiftUI

/// Read-only full-size viewer (or player, for recordings) with Copy (images only) and Delete.
/// There are no editing affordances.
///
/// Shows the thumbnail at once and swaps to the original when its download lands in `imageURLs`.
/// Offline without a cached original it keeps the thumbnail and says why.
struct RemoteScreenshotDetailView: View {
    let store: StoreOf<RemoteScreenshotsFeature>

    var body: some View {
        NavigationStack {
            Group {
                if let id = store.selectedItemID, let item = store.state.item(id) {
                    RemoteScreenshotDetailContent(store: store, item: item)
                } else {
                    Color.clear
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
                if let id = store.selectedItemID {
                    ToolbarItemGroup(placement: .bottomBar) {
                        if store.state.item(id)?.isRecording == false {
                            Button(
                                store.copiedItemID == id ? "Copied" : "Copy",
                                systemImage: store.copiedItemID == id ? "checkmark" : "doc.on.doc"
                            ) {
                                store.send(.copyTapped(id))
                            }
                        }
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.send(.deleteTapped(id))
                        }
                        .disabled(store.canDelete == false || store.state.isDeleting(id))
                    }
                }
            }
        }
        .modifier(RemoteScreenshotPromptsModifier(store: store, isActive: true))
    }

    private func dismiss() { store.send(.detailDismissed) }
}
