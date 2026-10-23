public enum DesktopPetPlaybackSource: CaseIterable, Hashable, Sendable {
    case appleMusic
    case spotify
    case radio

    public static func preferred(in sources: Set<Self>) -> Self? {
        allCases.first(where: sources.contains)
    }
}
