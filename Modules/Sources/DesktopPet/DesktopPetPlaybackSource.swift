public enum DesktopPetPlaybackSource: CaseIterable, Hashable, Sendable {
    case appleMusic
    case spotify
    case radio

    /// Playing sources win by priority; otherwise the displayed paused source is kept
    /// so the controls do not jump between paused players.
    public static func preferred(
        in statuses: [Self: DesktopPetPlaybackStatus],
        current: Self? = nil
    ) -> Self? {
        if let playing = allCases.first(where: { statuses[$0] == .playing }) {
            return playing
        }
        if let current, statuses[current] == .paused {
            return current
        }
        return allCases.first { statuses[$0] == .paused }
    }
}
