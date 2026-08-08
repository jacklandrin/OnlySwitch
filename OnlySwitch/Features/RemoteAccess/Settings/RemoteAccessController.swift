import Foundation

actor RemoteAccessController {
    private enum Lifecycle: Equatable {
        case idle
        case starting(UUID)
        case active
        case stopping(UUID)
        case terminal
    }

    private let remoteHost: RemoteHostClient
    private let configuration: @Sendable () async -> RemoteAccessPreferences
    private var lifecycle: Lifecycle = .idle

    init(
        remoteHost: RemoteHostClient = .live,
        preferences: RemoteAccessPreferencesClient = .liveValue,
        configuration: (@Sendable () async -> RemoteAccessPreferences)? = nil
    ) {
        self.remoteHost = remoteHost
        self.configuration = configuration ?? { preferences.load() }
    }

    func startIfEnabled() async {
        guard lifecycle != .terminal else { return }
        let token = UUID()
        lifecycle = .starting(token)
        let settings = await configuration()
        guard !Task.isCancelled, lifecycle == .starting(token) else { return }
        guard settings.isEnabled else {
            lifecycle = .idle
            return
        }
        do {
            try await remoteHost.start(.init(displayName: settings.displayName))
            if !Task.isCancelled, lifecycle == .starting(token) {
                lifecycle = .active
            } else {
                await remoteHost.stop()
            }
        } catch is CancellationError {
            return
        } catch {
            if lifecycle == .starting(token) {
                lifecycle = .idle
            }
        }
    }

    func stop() async {
        guard lifecycle != .terminal else { return }
        let token = UUID()
        lifecycle = .stopping(token)
        await remoteHost.stop()
        if lifecycle == .stopping(token) {
            lifecycle = .idle
        }
    }

    func stopForTermination() async {
        lifecycle = .terminal
        await remoteHost.stop()
    }
}
