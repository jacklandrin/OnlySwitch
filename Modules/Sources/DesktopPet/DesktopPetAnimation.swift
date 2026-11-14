/// The animations every desktop pet skin must draw. The raw values are a public skin contract:
/// Phase 2 HTML pets read them from `data-state`, so never rename a case's raw value.
public enum DesktopPetAnimation: String, CaseIterable, Sendable {
    case idle
    case focus
    case breakTime = "break"
    case music
    case working
    case hungry
    case eating
    case petted
    case dragging
}

/// A short, user-triggered expression that temporarily overrides ongoing activity.
public enum DesktopPetReaction: String, Equatable, Sendable {
    case eating
    case petted
}

/// Everything that decides how the pet looks. `animation` picks the single primary state;
/// the other fields stay available as modifiers (Pomodoro halo, Only Control switch, hunger badge).
public struct DesktopPetAnimationState: Equatable, Sendable {
    public var pomodoroPhase: DesktopPetPomodoroPhase?
    public var isMusicPlaying: Bool
    public var isAgentWorking: Bool
    public var isHungry: Bool
    public var reaction: DesktopPetReaction?
    public var isDragging: Bool
    public var isControlPresented: Bool

    public init(
        pomodoroPhase: DesktopPetPomodoroPhase? = nil,
        isMusicPlaying: Bool = false,
        isAgentWorking: Bool = false,
        isHungry: Bool = false,
        reaction: DesktopPetReaction? = nil,
        isDragging: Bool = false,
        isControlPresented: Bool = false
    ) {
        self.pomodoroPhase = pomodoroPhase
        self.isMusicPlaying = isMusicPlaying
        self.isAgentWorking = isAgentWorking
        self.isHungry = isHungry
        self.reaction = reaction
        self.isDragging = isDragging
        self.isControlPresented = isControlPresented
    }

    /// Priority: dragging > reaction > working > music > hungry > Pomodoro > idle.
    public var animation: DesktopPetAnimation {
        if isDragging { return .dragging }
        switch reaction {
        case .eating: return .eating
        case .petted: return .petted
        case nil: break
        }
        if isAgentWorking { return .working }
        if isMusicPlaying { return .music }
        if isHungry { return .hungry }
        switch pomodoroPhase {
        case .focus: return .focus
        case .breakTime: return .breakTime
        case nil: return .idle
        }
    }
}

extension DesktopPetAnimationState {
    /// Localization key describing the pet's needs. Hunger stays reported while other activity runs.
    var accessibilityStatusKey: String? {
        switch reaction {
        case .eating: return "Desktop pet eating"
        case .petted: return "Desktop pet enjoying pets"
        case nil: return isHungry ? "Desktop pet hungry" : nil
        }
    }
}
