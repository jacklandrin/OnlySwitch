import Observation

@MainActor
@Observable
final class DesktopPetPresentation {
    var isActive = false
    var isDragging = false
    var isControlPresented = false
    var pomodoroState: DesktopPetPomodoroState?
}
