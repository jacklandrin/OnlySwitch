import Dependencies
import Foundation

public struct SystemMonitorClient: Sendable {
    public var snapshots: @Sendable () -> AsyncThrowingStream<SystemMonitorSnapshot, Error>
    public var activateProcess: @MainActor @Sendable (SystemMonitorProcessActivationTarget) -> SystemMonitorProcessActivationOutcome

    public init(
        activateProcess: @escaping @MainActor @Sendable (SystemMonitorProcessActivationTarget) -> SystemMonitorProcessActivationOutcome = { _ in .unavailable },
        snapshots: @escaping @Sendable () -> AsyncThrowingStream<SystemMonitorSnapshot, Error>
    ) {
        self.activateProcess = activateProcess
        self.snapshots = snapshots
    }

    private static func finishedStream() -> AsyncThrowingStream<SystemMonitorSnapshot, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

extension SystemMonitorClient: DependencyKey {
    public static let liveValue = Self(snapshots: finishedStream)
    public static let testValue = Self(snapshots: finishedStream)
}

extension DependencyValues {
    public var systemMonitor: SystemMonitorClient {
        get { self[SystemMonitorClient.self] }
        set { self[SystemMonitorClient.self] = newValue }
    }
}
