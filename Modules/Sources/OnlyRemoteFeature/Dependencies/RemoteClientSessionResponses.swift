import Foundation
import RemoteCore

actor RemoteActionResponses {
    typealias Stream = AsyncThrowingStream<RemoteActionResult, Swift.Error>
    private var continuations: [UUID: Stream.Continuation] = [:]

    func register(_ id: UUID) -> Stream {
        let (stream, continuation) = Stream.makeStream(of: RemoteActionResult.self, bufferingPolicy: .bufferingNewest(1))
        continuations[id]?.finish(throwing: CancellationError())
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.cancel(id) } }
        return stream
    }

    func resolve(_ result: RemoteActionResult) {
        guard let continuation = continuations.removeValue(forKey: result.requestID) else { return }
        continuation.yield(result)
        continuation.finish()
    }

    func cancel(_ id: UUID) { continuations.removeValue(forKey: id)?.finish(throwing: CancellationError()) }

    func finishAll() {
        let values = continuations.values
        continuations.removeAll()
        for continuation in values { continuation.finish(throwing: CancellationError()) }
    }
}

actor RemoteCodexUsageResponses {
    typealias Stream = AsyncThrowingStream<RemoteCodexUsageResult, Swift.Error>
    struct Registration: Sendable {
        let token: UUID
        let stream: Stream
    }
    private struct Pending: Sendable {
        let token: UUID
        let continuation: Stream.Continuation
    }
    private var continuations: [UUID: Pending] = [:]
    func register(_ id: UUID) -> Registration {
        let (stream, continuation) = Stream.makeStream(of: RemoteCodexUsageResult.self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        continuations[id]?.continuation.finish(throwing: CancellationError())
        continuations[id] = Pending(token: token, continuation: continuation)
        continuation.onTermination = { [weak self] _ in Task { await self?.cancel(id, token: token) } }
        return Registration(token: token, stream: stream)
    }
    func resolve(_ result: RemoteCodexUsageResult) {
        guard let pending = continuations.removeValue(forKey: result.requestID) else { return }
        pending.continuation.yield(result)
        pending.continuation.finish()
    }
    func cancel(_ id: UUID, token: UUID) {
        guard continuations[id]?.token == token else { return }
        continuations.removeValue(forKey: id)?.continuation.finish(throwing: CancellationError())
    }
    func finishAll() {
        let values = continuations.values
        continuations.removeAll()
        for pending in values { pending.continuation.finish(throwing: CancellationError()) }
    }
}
actor RemoteClaudeUsageResponses {
    typealias Stream = AsyncThrowingStream<RemoteClaudeUsageResult, Swift.Error>
    struct Registration: Sendable {
        let token: UUID
        let stream: Stream
    }
    private struct Pending: Sendable {
        let token: UUID
        let continuation: Stream.Continuation
    }
    private var continuations: [UUID: Pending] = [:]
    func register(_ id: UUID) -> Registration {
        let (stream, continuation) = Stream.makeStream(of: RemoteClaudeUsageResult.self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        continuations[id]?.continuation.finish(throwing: CancellationError())
        continuations[id] = Pending(token: token, continuation: continuation)
        continuation.onTermination = { [weak self] _ in Task { await self?.cancel(id, token: token) } }
        return Registration(token: token, stream: stream)
    }
    func resolve(_ result: RemoteClaudeUsageResult) {
        guard let pending = continuations.removeValue(forKey: result.requestID) else { return }
        pending.continuation.yield(result)
        pending.continuation.finish()
    }
    func cancel(_ id: UUID, token: UUID) {
        guard continuations[id]?.token == token else { return }
        continuations.removeValue(forKey: id)?.continuation.finish(throwing: CancellationError())
    }
    func finishAll() {
        let values = continuations.values
        continuations.removeAll()
        for pending in values { pending.continuation.finish(throwing: CancellationError()) }
    }
}
