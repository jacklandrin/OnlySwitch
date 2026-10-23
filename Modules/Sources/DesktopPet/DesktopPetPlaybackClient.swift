import Dependencies

public struct DesktopPetPlaybackClient: Sendable {
    public var playingSources: @MainActor @Sendable () -> Set<DesktopPetPlaybackSource>
    public var next: @MainActor @Sendable (DesktopPetPlaybackSource) -> Void

    public init(
        playingSources: @escaping @MainActor @Sendable () -> Set<DesktopPetPlaybackSource> = { [] },
        next: @escaping @MainActor @Sendable (DesktopPetPlaybackSource) -> Void = { _ in }
    ) {
        self.playingSources = playingSources
        self.next = next
    }
}

extension DesktopPetPlaybackClient: DependencyKey {
    public static let liveValue = Self()
    public static let testValue = Self()
}

extension DependencyValues {
    public var desktopPetPlayback: DesktopPetPlaybackClient {
        get { self[DesktopPetPlaybackClient.self] }
        set { self[DesktopPetPlaybackClient.self] = newValue }
    }
}
