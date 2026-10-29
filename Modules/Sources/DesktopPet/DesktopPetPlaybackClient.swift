import Dependencies

public struct DesktopPetPlaybackClient: Sendable {
    public var statuses: @MainActor @Sendable () -> [DesktopPetPlaybackSource: DesktopPetPlaybackStatus]
    public var next: @MainActor @Sendable (DesktopPetPlaybackSource) -> Void
    public var play: @MainActor @Sendable (DesktopPetPlaybackSource) -> Void
    public var pause: @MainActor @Sendable (DesktopPetPlaybackSource) -> Void

    public init(
        statuses: @escaping @MainActor @Sendable () -> [DesktopPetPlaybackSource: DesktopPetPlaybackStatus] = { [:] },
        next: @escaping @MainActor @Sendable (DesktopPetPlaybackSource) -> Void = { _ in },
        play: @escaping @MainActor @Sendable (DesktopPetPlaybackSource) -> Void = { _ in },
        pause: @escaping @MainActor @Sendable (DesktopPetPlaybackSource) -> Void = { _ in }
    ) {
        self.statuses = statuses
        self.next = next
        self.play = play
        self.pause = pause
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
