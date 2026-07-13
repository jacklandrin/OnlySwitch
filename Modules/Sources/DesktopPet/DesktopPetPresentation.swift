import Observation

@MainActor
@Observable
final class DesktopPetPresentation {
    var isActive = false
    var isDragging = false
}
