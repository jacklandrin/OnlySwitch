import Dependencies
import Foundation
import RemoteCore

struct RemoteScreenshotImageClient: Sendable {
    /// Cached original, else downloads it from the selected Mac, verifies it and caches it.
    ///
    /// Concurrent loads of the same Mac + item + revision share one download (the Mac serves one
    /// original at a time and a newer request supersedes the previous one). `CancellationError`
    /// is rethrown unchanged: it means the caller was cancelled, the transfer was superseded, or
    /// the session unsubscribed/disconnected.
    var load: @Sendable (_ macID: UUID, RemoteScreenshotItem) async throws -> URL

    static let unavailable = Self { _, _ in throw RemoteDependencyError.unimplemented }

    static func live(
        cache: RemoteScreenshotCacheClient,
        fetchImage: @escaping @Sendable (RemoteScreenshotInvocation<RemoteScreenshotImageRequest>) async throws -> RemoteScreenshotImagePayload,
        holdTransfer: @escaping @Sendable (_ transfer: @escaping @Sendable () async throws -> URL) async throws -> URL = { try await $0() },
        makeRequestID: @escaping @Sendable () -> UUID
    ) -> Self {
        let loads = RemoteScreenshotImageLoads()
        return Self { macID, item in
            if let cached = await cache.imageURL(macID, item) { return cached }
            let key = RemoteScreenshotImageLoads.Key(macID: macID, itemID: item.id, revision: item.revision)
            return try await loads.load(key) {
                // One hold per flight, covering the download and the cache write, so a drop that
                // asks for the file after the app was backgrounded can still be served.
                try await holdTransfer {
                    // Another flight may have finished between the cache check and joining.
                    if let cached = await cache.imageURL(macID, item) { return cached }
                    let payload = try await fetchImage(.init(
                        macID: macID,
                        request: .init(requestID: makeRequestID(), itemID: item.id, revision: item.revision)
                    ))
                    return try await cache.saveImage(macID, item, payload.data)
                }
            }
        }
    }
}

extension RemoteScreenshotImageClient: DependencyKey {
    static var liveValue: Self {
        @Dependency(\.remoteConnection) var connection
        @Dependency(\.remoteScreenshotCache) var cache
        return .live(
            cache: cache,
            fetchImage: { try await connection.fetchScreenshotImage($0) },
            holdTransfer: { try await connection.withBackgroundTransferHold($0) },
            makeRequestID: { UUID() }
        )
    }

    static var testValue: Self { .unavailable }
}

extension DependencyValues {
    var remoteScreenshotImages: RemoteScreenshotImageClient {
        get { self[RemoteScreenshotImageClient.self] }
        set { self[RemoteScreenshotImageClient.self] = newValue }
    }
}

/// Single-flight coordinator for original downloads, keyed by Mac + item + revision.
///
/// Semantics:
/// - The first caller for a key starts the download in an unstructured task; later callers join it.
/// - Every waiter receives the download's result, errors included (unchanged, so `CancellationError`
///   stays `CancellationError`). Results are not remembered: success lands in the file cache, and a
///   failure lets the next caller start a fresh download.
/// - A cancelled waiter stops waiting immediately with `CancellationError`. The shared download keeps
///   running while other waiters remain, and is cancelled when the last waiter leaves.
actor RemoteScreenshotImageLoads {
    struct Key: Hashable, Sendable {
        let macID: UUID
        let itemID: UUID
        let revision: Int
    }

    private struct Flight {
        let token: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<URL, any Swift.Error>]
    }

    private var flights: [Key: Flight] = [:]

    func waiterCount(for key: Key) -> Int {
        flights[key]?.waiters.count ?? 0
    }

    func load(_ key: Key, operation: @escaping @Sendable () async throws -> URL) async throws -> URL {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                join(key, waiterID: waiterID, continuation: continuation, operation: operation)
            }
        } onCancel: {
            Task { await self.leave(key, waiterID: waiterID) }
        }
    }

    private func join(
        _ key: Key,
        waiterID: UUID,
        continuation: CheckedContinuation<URL, any Swift.Error>,
        operation: @escaping @Sendable () async throws -> URL
    ) {
        // A caller cancelled before joining would otherwise miss its cancellation handler's hop.
        guard Task.isCancelled == false else {
            continuation.resume(throwing: CancellationError())
            return
        }
        if var flight = flights[key] {
            flight.waiters[waiterID] = continuation
            flights[key] = flight
            return
        }
        let token = UUID()
        let task = Task {
            let result: Result<URL, any Swift.Error>
            do { result = .success(try await operation()) } catch { result = .failure(error) }
            self.finish(key, token: token, result: result)
        }
        flights[key] = Flight(token: token, task: task, waiters: [waiterID: continuation])
    }

    private func leave(_ key: Key, waiterID: UUID) {
        guard var flight = flights[key], let continuation = flight.waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            flights[key] = nil
            flight.task.cancel()
        } else {
            flights[key] = flight
        }
    }

    private func finish(_ key: Key, token: UUID, result: Result<URL, any Swift.Error>) {
        guard let flight = flights[key], flight.token == token else { return }
        flights[key] = nil
        for continuation in flight.waiters.values { continuation.resume(with: result) }
    }
}
