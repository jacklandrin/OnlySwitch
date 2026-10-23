import SwiftUI
import ComposableArchitecture

struct DesktopPetRootView: View {
    let presentation: DesktopPetPresentation
    let onDragChanged: @MainActor (DragGesture.Value) -> Void
    let onDragEnded: @MainActor (DragGesture.Value) -> Void
    let playbackStore: StoreOf<DesktopPetPlaybackFeature>
    let onPlaybackVisibilityChanged: @MainActor (Bool) -> Void
    let onClose: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if playbackStore.source != nil {
                DesktopPetPlaybackButton {
                    playbackStore.send(.nextTapped)
                }
                .padding(.top, 2)
                .frame(
                    height: DesktopPetMetrics.playbackLaneHeight(for: presentation.pomodoroState),
                    alignment: .top
                )
            }
            pet
        }
        .onChange(of: playbackStore.source != nil, initial: true) { _, isShown in
            onPlaybackVisibilityChanged(isShown)
        }
    }

    private var pet: some View {
        DesktopPetView(
            isActive: presentation.isActive,
            isDragging: presentation.isDragging,
            isControlPresented: presentation.isControlPresented,
            pomodoroState: presentation.pomodoroState,
            isMusicPlaying: playbackStore.source != nil
        )
        .contentShape(
            .interaction,
            DesktopPetInteractionShape(
                size: DesktopPetMetrics.interactionSize(for: presentation.pomodoroState)
            )
        )
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged(onDragChanged)
                .onEnded(onDragEnded)
        )
        .contextMenu {
            Button("Close", role: .destructive, action: onClose)
        }
    }

}
