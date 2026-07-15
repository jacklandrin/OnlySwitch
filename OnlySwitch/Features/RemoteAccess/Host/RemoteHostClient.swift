import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct RemoteHostClient: Sendable {
    var start: @Sendable (RemoteHostConfiguration) async throws -> Void
    var stop: @Sendable () async -> Void
    var startPairing: @Sendable () async throws -> PairingWindow
    var cancelPairing: @Sendable () async -> Void
    var revoke: @Sendable (UUID) async throws -> Void
    var pairedDevices: @Sendable () async throws -> [PairedRemoteDevice]
    var events: @Sendable () -> AsyncStream<RemoteHostEvent> = { .finished }
}

extension RemoteHostClient: DependencyKey {
    static var liveValue: Self { .live }
    static var testValue: Self { Self() }
}

extension RemoteHostClient {
    static var live: Self {
        Self(
            start: { configuration in
                let host = await MainActor.run { RemoteHost.shared }
                try await host.start(configuration: configuration)
            },
            stop: {
                let host = await MainActor.run { RemoteHost.shared }
                await host.stop()
            },
            startPairing: {
                let host = await MainActor.run { RemoteHost.shared }
                return await host.startPairing()
            },
            cancelPairing: {
                let host = await MainActor.run { RemoteHost.shared }
                await host.cancelPairing()
            },
            revoke: { id in
                let host = await MainActor.run { RemoteHost.shared }
                try await host.revoke(deviceID: id)
            },
            pairedDevices: {
                let host = await MainActor.run { RemoteHost.shared }
                return try await host.pairedDevices()
            },
            events: {
                AsyncStream { continuation in
                    let task = Task {
                        let host = await MainActor.run { RemoteHost.shared }
                        for await event in host.events {
                            guard Task.isCancelled == false else { break }
                            continuation.yield(event)
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }
}

extension DependencyValues {
    var remoteHost: RemoteHostClient {
        get { self[RemoteHostClient.self] }
        set { self[RemoteHostClient.self] = newValue }
    }
}
