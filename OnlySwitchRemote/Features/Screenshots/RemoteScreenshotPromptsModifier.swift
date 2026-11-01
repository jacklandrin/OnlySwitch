import ComposableArchitecture
import SwiftUI

/// The delete confirmation and the operation error alert. Applied both to the grid and to the
/// detail sheet; `isActive` makes sure only the frontmost of the two presents them.
struct RemoteScreenshotPromptsModifier: ViewModifier {
    let store: StoreOf<RemoteScreenshotsFeature>
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Move this screenshot to the Trash on the Mac?",
                isPresented: deleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive, action: confirmDelete)
                Button("Cancel", role: .cancel, action: cancelDelete)
            } message: {
                Text("It can be restored from the Trash on the Mac.")
            }
            .alert(
                "Screenshots",
                isPresented: errorPresented,
                actions: { Button("OK", action: dismissError) },
                message: { Text(verbatim: store.operationError ?? "") }
            )
    }

    private func confirmDelete() { store.send(.deleteConfirmed) }
    private func cancelDelete() { store.send(.deleteCancelled) }
    private func dismissError() { store.send(.errorDismissed) }

    // The reducer can clear these on its own (for example when a new library drops the item).
    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { isActive && store.pendingDeleteItemID != nil },
            set: { if $0 == false, isActive, store.pendingDeleteItemID != nil { store.send(.deleteCancelled) } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { isActive && store.operationError != nil },
            set: { if $0 == false, isActive, store.operationError != nil { store.send(.errorDismissed) } }
        )
    }
}
