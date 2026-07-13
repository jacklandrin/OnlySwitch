import SwiftUI

struct DesktopPetRootView: View {
    let presentation: DesktopPetPresentation
    let onDragChanged: @MainActor (DragGesture.Value) -> Void
    let onDragEnded: @MainActor (DragGesture.Value) -> Void

    var body: some View {
        DesktopPetView(
            isActive: presentation.isActive,
            isDragging: presentation.isDragging,
            isControlPresented: presentation.isControlPresented
        )
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged(onDragChanged)
                .onEnded(onDragEnded)
        )
    }
}
