import DesktopPetSkinKit
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
    /// Whether the pet panel is on screen; edge docking may still pause it via `isActive`.
    var isShown = false
    /// The custom skin to show instead of the built-in pet.
    var skin: DesktopPetSkin?
    /// The skin to render. `nil` while hidden, so the skin's web view exists only while it is shown.
    var renderedSkin: DesktopPetSkin? { isShown ? skin : nil }
}
