public enum DesktopPetPomodoroPhase: Equatable, Sendable {
    case focus
    case breakTime
}

public struct DesktopPetPomodoroState: Equatable, Sendable {
    public let phase: DesktopPetPomodoroPhase
    public let remainingTime: String

    public init(phase: DesktopPetPomodoroPhase, remainingTime: String) {
        self.phase = phase
        self.remainingTime = remainingTime
    }
}
