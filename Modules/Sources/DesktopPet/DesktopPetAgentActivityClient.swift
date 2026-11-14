import Dependencies
import Foundation

public struct DesktopPetAgentActivityClient: Sendable {
    public var updates: @Sendable () -> AsyncStream<DesktopPetAgentUpdate>

    public init(updates: @escaping @Sendable () -> AsyncStream<DesktopPetAgentUpdate> = { .finished }) {
        self.updates = updates
    }
}

extension DesktopPetAgentActivityClient: DependencyKey {
    public static let liveValue = Self {
        let (stream, continuation) = AsyncStream.makeStream(
            of: DesktopPetAgentUpdate.self, bufferingPolicy: .bufferingNewest(8)
        )
        let monitor = DesktopPetAgentLogMonitor()
        let task = Task {
            defer { continuation.finish() }
            do {
                while !Task.isCancelled {
                    let update = await monitor.scan(at: Date())
                    try Task.checkCancellation()
                    continuation.yield(update)
                    try await Task.sleep(for: .seconds(2))
                }
            } catch is CancellationError {
                // Ending a subscription is an ordinary desktop-pet visibility change.
            } catch {
                // Filesystem failures are represented by unavailable events, never success.
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
    public static let testValue = Self()
}

extension DependencyValues {
    public var desktopPetAgentActivity: DesktopPetAgentActivityClient {
        get { self[DesktopPetAgentActivityClient.self] }
        set { self[DesktopPetAgentActivityClient.self] = newValue }
    }
}
