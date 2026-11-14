import SwiftUI

public struct DesktopPetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isActive: Bool
    private let isDragging: Bool
    private let isControlPresented: Bool
    private let pomodoroState: DesktopPetPomodoroState?
    private let isMusicPlaying: Bool
    private let workingAgents: [DesktopPetAgent]

    public init(
        isActive: Bool = true,
        isDragging: Bool = false,
        isControlPresented: Bool = false,
        pomodoroState: DesktopPetPomodoroState? = nil,
        isMusicPlaying: Bool = false,
        workingAgents: [DesktopPetAgent] = []
    ) {
        self.isActive = isActive
        self.isDragging = isDragging
        self.isControlPresented = isControlPresented
        self.pomodoroState = pomodoroState
        self.isMusicPlaying = isMusicPlaying
        self.workingAgents = workingAgents
    }

    public var body: some View {
        TimelineView(
            .animation(
                minimumInterval: DesktopPetRefreshPolicy.minimumInterval,
                paused: DesktopPetRefreshPolicy.isPaused(
                    isActive: isActive,
                    isDragging: isDragging,
                    reduceMotion: reduceMotion
                )
            )
        ) { context in
            let motion = DesktopPetMotion.values(
                at: context.date,
                pomodoroState: pomodoroState,
                isActive: isActive,
                isDragging: isDragging,
                reduceMotion: reduceMotion,
                isMusicPlaying: isMusicPlaying,
                isAgentWorking: !workingAgents.isEmpty
            )

            ZStack(alignment: .top) {
                DesktopPetArtwork(
                    motion: motion,
                    pomodoroPhase: pomodoroState?.phase,
                    isControlPresented: isControlPresented,
                    isDragging: isDragging,
                    reduceMotion: reduceMotion,
                    isMusicPlaying: isMusicPlaying,
                    isAgentWorking: !workingAgents.isEmpty
                )
                .frame(
                    width: DesktopPetMetrics.artworkSize.width,
                    height: DesktopPetMetrics.artworkSize.height
                )
                .offset(
                    y: DesktopPetMetrics.artworkOffsetY(for: pomodoroState)
                )

                if let pomodoroState {
                    DesktopPetPomodoroBadge(
                        state: pomodoroState,
                        motion: motion
                    )
                    .frame(height: DesktopPetMetrics.pomodoroTimerLane.height)
                }
            }
        }
        .frame(
            width: DesktopPetMetrics.canvasSize(for: pomodoroState).width,
            height: DesktopPetMetrics.canvasSize(for: pomodoroState).height,
            alignment: .top
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Click to toggle Only Control. Drag to move.")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        var values = [pomodoroState?.remainingTime].compactMap(\.self)
        if !workingAgents.isEmpty {
            values.append(workingAgents.map(\.name).joined(separator: ", "))
            values.append(String(localized: "Agent working", bundle: .main))
        }
        return values.joined(separator: ", ")
    }

    private var accessibilityLabel: Text {
        guard let pomodoroState else {
            return Text(isControlPresented ? "Hide Only Control" : "Show Only Control")
        }

        switch pomodoroState.phase {
        case .focus:
            return Text(String(localized: "Desktop pet focus timer", bundle: .main))
        case .breakTime:
            return Text(String(localized: "Desktop pet break timer", bundle: .main))
        }
    }
}
