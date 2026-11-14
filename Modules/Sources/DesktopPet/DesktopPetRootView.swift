import SwiftUI
import ComposableArchitecture

struct DesktopPetRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: DesktopPetPresentation
    let onDragChanged: @MainActor (DragGesture.Value) -> Void
    let onDragEnded: @MainActor (DragGesture.Value) -> Void
    let playbackStore: StoreOf<DesktopPetPlaybackFeature>
    let activityStore: StoreOf<DesktopPetAgentActivityFeature>
    let onPlaybackVisibilityChanged: @MainActor (Bool) -> Void
    let onActivityVisibilityChanged: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: DesktopPetMetrics.agentStatusGap) {
            if let completion = activityStore.completion {
                DesktopPetAgentActivityBubble(
                    completion: completion,
                    onDismiss: {
                        activityStore.send(.dismissCompletion(id: completion.id))
                    }
                )
                .padding(.bottom, DesktopPetMetrics.agentStatusBottomPadding(for: presentation.pomodoroState))
            }
            petColumn
        }
        .onChange(of: playbackStore.source != nil, initial: true) { _, isShown in
            onPlaybackVisibilityChanged(isShown)
        }
        .onChange(of: activityStore.showsStatus) { _, _ in onActivityVisibilityChanged() }
    }

    private var petColumn: some View {
        VStack(spacing: 0) {
            if playbackStore.source != nil {
                DesktopPetNowPlayingLabel(
                    nowPlaying: playbackStore.nowPlaying,
                    onOpen: openPlayer
                )
                    .frame(height: DesktopPetMetrics.nowPlayingLaneHeight, alignment: .top)
                DesktopPetPlaybackControls(
                    isPlaying: playbackStore.isPlaying,
                    onPlayPause: { playbackStore.send(.playPauseTapped) },
                    onNext: { playbackStore.send(.nextTapped) }
                )
                .padding(.top, 2)
                .frame(
                    height: DesktopPetMetrics.playbackLaneHeight(for: presentation.pomodoroState),
                    alignment: .top
                )
            }
            pet
        }
    }

    private var openPlayer: (@MainActor () -> Void)? {
        guard playbackStore.source?.hasPlayerApp == true else { return nil }
        return { playbackStore.send(.nowPlayingTapped) }
    }

    private var pet: some View {
        DesktopPetView(
            isActive: presentation.isActive,
            isDragging: presentation.isDragging,
            isControlPresented: presentation.isControlPresented,
            pomodoroState: presentation.pomodoroState,
            isMusicPlaying: playbackStore.isPlaying,
            workingAgents: activityStore.runningAgents
        )
        .rotationEffect(.degrees(presentation.edgeTilt))
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.4),
            value: presentation.edgeTilt
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
