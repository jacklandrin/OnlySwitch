/// Version 1 of the desktop pet skin contract. A skin is CSS + markup that reacts only to
/// host-set attributes on `<html>`; see ARCHITECTURE.md "Desktop pet skins".
public enum DesktopPetSkinContract {
    public static let version = 1
    public static let requiredStates = [
        "idle", "focus", "break", "music", "working", "hungry", "eating", "petted", "dragging"
    ]
    public static let canvasWidth = 120
    public static let canvasHeight = 130
    public static let rootElementID = "pet"
    public static let maximumMarkupBytes = 65_536
}
