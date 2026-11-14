import SwiftUI
import ComposableArchitecture

struct DesktopPetRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: DesktopPetPresentation
    let onDragChanged: @MainActor (DragGesture.Value) -> Void
    let onDragEnded: @MainActor (DragGesture.Value) -> Void
    let playbackStore: StoreOf<DesktopPetPlaybackFeature>
    let activityStore: StoreOf<DesktopPetAgentActivityFeature>
    let needsStore: StoreOf<DesktopPetNeedsFeature>
    let onPlaybackVisibilityChanged: @MainActor (Bool) -> Void
    let onActivityVisibilityChanged: @MainActor () -> Void
    let onNeedsChanged: @MainActor () -> Void
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
        .onChange(of: needsStore.isHungry) { _, _ in onNeedsChanged() }
        .onChange(of: needsStore.reaction) { _, _ in onNeedsChanged() }
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
            workingAgents: activityStore.runningAgents,
            isHungry: needsStore.isHungry,
            reaction: needsStore.reaction,
            reactionStartedAt: needsStore.reactionStartedAt,
            skin: presentation.skin
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
            if needsStore.isHungerEnabled {
                Button("Desktop Pet Feed", systemImage: "fork.knife") { needsStore.send(.feedTapped) }
            }
            Button("Desktop Pet Pat", systemImage: "hand.raised.fill") { needsStore.send(.petTapped) }
            Divider()
            Button("Close", role: .destructive, action: onClose)
        }
        .accessibilityAction(named: Text("Desktop Pet Pat")) { needsStore.send(.petTapped) }
        .modifier(DesktopPetFeedAccessibilityAction(isEnabled: needsStore.isHungerEnabled) {
            needsStore.send(.feedTapped)
        })
    }
}

/// Exposes Feed to assistive technologies only while hunger is on, matching the context menu.
private struct DesktopPetFeedAccessibilityAction: ViewModifier {
    let isEnabled: Bool
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityAction(named: Text("Desktop Pet Feed"), action)
        } else {
            content
        }
    }
}
