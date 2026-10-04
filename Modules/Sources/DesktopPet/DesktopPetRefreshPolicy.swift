enum DesktopPetRefreshPolicy {
    static let minimumInterval = 1.0 / 15.0

    static func isPaused(
        isActive: Bool,
        isDragging: Bool,
        reduceMotion: Bool
    ) -> Bool {
        !isActive || isDragging || reduceMotion
    }
}
