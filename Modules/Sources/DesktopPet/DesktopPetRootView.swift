import SwiftUI

struct DesktopPetRootView: View {
    let presentation: DesktopPetPresentation
    let onDragChanged: @MainActor (DragGesture.Value) -> Void
    let onDragEnded: @MainActor (DragGesture.Value) -> Void

    var body: some View {
        ZStack {
            DesktopPetView(
                isActive: presentation.isActive,
                isDragging: presentation.isDragging,
                isControlPresented: presentation.isControlPresented
            )
            .allowsHitTesting(false)

            Color.clear
                .frame(
                    width: DesktopPetMetrics.artworkFrame.width,
                    height: DesktopPetMetrics.artworkFrame.height
                )
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged(onDragChanged)
                        .onEnded(onDragEnded)
                )
        }
    }
}
