import CryptoKit
import Foundation
import RemoteCore

struct RemoteAphroditeTransferAccumulator: Sendable {
    let manifest: AphroditeRemoteLibraryManifest
    private var chunks: [UUID: [Int: Data]] = [:]

    init(manifest: AphroditeRemoteLibraryManifest) {
        self.manifest = manifest
    }

    mutating func append(_ chunk: AphroditeRemoteDocumentChunk) throws {
        guard chunk.transferID == manifest.transferID,
              let descriptor = manifest.documents.first(where: { $0.appID == chunk.appID }),
              chunk.index < descriptor.chunkCount,
              chunks[chunk.appID]?[chunk.index] == nil,
              (chunks[chunk.appID]?.values.reduce(0) { $0 + $1.count } ?? 0) + chunk.data.count <= descriptor.byteCount else {
            throw AphroditeRemoteValidationError.invalidChunk
        }
        chunks[chunk.appID, default: [:]][chunk.index] = chunk.data
    }

    func complete() throws -> AphroditeRemoteLibrarySnapshot {
        let decoder = JSONDecoder()
        let apps = try manifest.documents.map { descriptor in
            guard let documentChunks = chunks[descriptor.appID], documentChunks.count == descriptor.chunkCount else {
                throw AphroditeRemoteValidationError.invalidChunk
            }
            var bytes = Data()
            bytes.reserveCapacity(descriptor.byteCount)
            for index in 0..<descriptor.chunkCount {
                guard let chunk = documentChunks[index], bytes.count + chunk.count <= descriptor.byteCount else {
                    throw AphroditeRemoteValidationError.invalidChunk
                }
                bytes.append(chunk)
            }
            guard bytes.count == descriptor.byteCount,
                  Data(SHA256.hash(data: bytes)) == descriptor.sha256 else {
                throw AphroditeRemoteValidationError.invalidDescriptor
            }
            let tool = try decoder.decode(AphroditePersonalTool.self, from: bytes)
            guard tool.id == descriptor.appID, tool.title == descriptor.title, tool.updatedAt == descriptor.updatedAt else {
                throw AphroditeRemoteValidationError.invalidDescriptor
            }
            return tool
        }
        return try AphroditeRemoteLibrarySnapshot(revision: manifest.revision, apps: apps).validated()
    }
}

final class RemoteStreamHub<Element: Sendable>: @unchecked Sendable {
    typealias Continuation = AsyncStream<Element>.Continuation

    private struct Subscriber {
        let continuation: Continuation
        let onNoSubscribers: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var subscribers: [UUID: Subscriber] = [:]

    var subscriberCount: Int {
        lock.withLock { subscribers.count }
    }

    func stream(
        bufferingPolicy: Continuation.BufferingPolicy,
        onFirstSubscriber: @escaping @Sendable () -> Void = {},
        onNoSubscribers: @escaping @Sendable () -> Void = {}
    ) -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Element.self,
            bufferingPolicy: bufferingPolicy
        )
        continuation.onTermination = { [weak self] _ in self?.removeSubscriber(id) }
        let isFirst = lock.withLock { () -> Bool in
            let isFirst = subscribers.isEmpty
            subscribers[id] = Subscriber(
                continuation: continuation,
                onNoSubscribers: onNoSubscribers
            )
            return isFirst
        }
        if isFirst { onFirstSubscriber() }
        return stream
    }

    func yield(_ element: Element) {
        let continuations = lock.withLock { subscribers.values.map(\.continuation) }
        for continuation in continuations { continuation.yield(element) }
    }

    private func removeSubscriber(_ id: UUID) {
        let onNoSubscribers = lock.withLock { () -> (@Sendable () -> Void)? in
            guard let removed = subscribers.removeValue(forKey: id), subscribers.isEmpty else { return nil }
            return removed.onNoSubscribers
        }
        onNoSubscribers?()
    }
}

actor RemoteLocalStateMutationCoordinator {
    private var tail: Task<Void, Never>?

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let preceding = tail
        let task = Task<Value, Swift.Error> {
            if let preceding { await preceding.value }
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
