import DesktopPetSkinKit
import SwiftUI

public struct DesktopPetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isActive: Bool
    private let isDragging: Bool
    private let isControlPresented: Bool
    private let pomodoroState: DesktopPetPomodoroState?
    private let isMusicPlaying: Bool
    private let workingAgents: [DesktopPetAgent]
    private let isHungry: Bool
    private let reaction: DesktopPetReaction?
    private let reactionStartedAt: Date?
    private let skin: DesktopPetSkin?

    public init(
        isActive: Bool = true,
        isDragging: Bool = false,
        isControlPresented: Bool = false,
        pomodoroState: DesktopPetPomodoroState? = nil,
        isMusicPlaying: Bool = false,
        workingAgents: [DesktopPetAgent] = [],
        isHungry: Bool = false,
        reaction: DesktopPetReaction? = nil,
        reactionStartedAt: Date? = nil,
        skin: DesktopPetSkin? = nil
    ) {
        self.isActive = isActive
        self.isDragging = isDragging
        self.isControlPresented = isControlPresented
        self.pomodoroState = pomodoroState
        self.isMusicPlaying = isMusicPlaying
        self.workingAgents = workingAgents
        self.isHungry = isHungry
        self.reaction = reaction
        self.reactionStartedAt = reactionStartedAt
        self.skin = skin
    }

    public var body: some View {
        TimelineView(
            .animation(
                minimumInterval: DesktopPetRefreshPolicy.minimumInterval,
                paused: skin != nil || DesktopPetRefreshPolicy.isPaused(
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
                isAgentWorking: !workingAgents.isEmpty,
                isHungry: isHungry,
                reaction: reaction,
                reactionStartedAt: reactionStartedAt
            )

            ZStack(alignment: .top) {
                Group {
                    if let skin {
                        DesktopPetSkinWebView(
                            skin: skin,
                            state: DesktopPetAnimationState(
                                pomodoroPhase: pomodoroState?.phase,
                                isMusicPlaying: isMusicPlaying,
                                isAgentWorking: !workingAgents.isEmpty,
                                isHungry: isHungry,
                                reaction: reaction,
                                isDragging: isDragging,
                                isControlPresented: isControlPresented
                            ),
                            reduceMotion: reduceMotion,
                            isPaused: !isActive
                        )
                    } else {
                        DesktopPetArtwork(
                            motion: motion,
                            pomodoroPhase: pomodoroState?.phase,
                            isControlPresented: isControlPresented,
                            isDragging: isDragging,
                            reduceMotion: reduceMotion,
                            isMusicPlaying: isMusicPlaying,
                            isAgentWorking: !workingAgents.isEmpty,
                            isHungry: isHungry,
                            reaction: reaction
                        )
                    }
                }
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
        let needs = DesktopPetAnimationState(isHungry: isHungry, reaction: reaction)
        if let key = needs.accessibilityStatusKey {
            values.append(Bundle.main.localizedString(forKey: key, value: nil, table: nil))
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
