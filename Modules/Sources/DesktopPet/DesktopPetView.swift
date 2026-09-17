import SwiftUI

public struct DesktopPetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isActive: Bool
    private let isDragging: Bool
    private let isControlPresented: Bool
    private let pomodoroState: DesktopPetPomodoroState?

    public init(
        isActive: Bool = true,
        isDragging: Bool = false,
        isControlPresented: Bool = false,
        pomodoroState: DesktopPetPomodoroState? = nil
    ) {
        self.isActive = isActive
        self.isDragging = isDragging
        self.isControlPresented = isControlPresented
        self.pomodoroState = pomodoroState
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: !isActive || isDragging || reduceMotion
                )
            ) { context in
                DesktopPetArtwork(
                    motion: DesktopPetMotion.values(
                        at: context.date,
                        pomodoroState: pomodoroState,
                        isActive: isActive,
                        isDragging: isDragging,
                        reduceMotion: reduceMotion
                    ),
                    pomodoroPhase: pomodoroState?.phase,
                    isControlPresented: isControlPresented,
                    isDragging: isDragging,
                    reduceMotion: reduceMotion
                )
                .frame(
                    width: DesktopPetMetrics.artworkSize.width,
                    height: DesktopPetMetrics.artworkSize.height
                )
            }
            .offset(
                y: DesktopPetMetrics.artworkOffsetY(for: pomodoroState)
            )

            if let pomodoroState {
                DesktopPetPomodoroBadge(
                    state: pomodoroState,
                    isActive: isActive,
                    isDragging: isDragging,
                    reduceMotion: reduceMotion
                )
                .frame(height: DesktopPetMetrics.pomodoroTimerLane.height)
            }
        }
        .frame(
            width: DesktopPetMetrics.canvasSize(for: pomodoroState).width,
            height: DesktopPetMetrics.canvasSize(for: pomodoroState).height,
            alignment: .top
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(pomodoroState?.remainingTime ?? "")
        .accessibilityHint("Click to toggle Only Control. Drag to move.")
        .accessibilityAddTraits(.isButton)
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
