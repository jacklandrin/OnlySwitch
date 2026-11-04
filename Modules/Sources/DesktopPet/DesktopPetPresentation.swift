import Observation

@MainActor
@Observable
final class DesktopPetPresentation {
    var isActive = false
    var isDragging = false
    var isControlPresented = false
    var pomodoroState: DesktopPetPomodoroState?
    /// Lean in degrees while the pet peeks out from behind a screen edge.
    var edgeTilt: Double = 0
}
