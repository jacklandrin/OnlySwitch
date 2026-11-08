import Foundation
import RemoteCore

enum RemoteScreenshotResponse: Equatable, Sendable {
    case thumbnails(RemoteScreenshotThumbnailsResult)
    case image(RemoteScreenshotImagePayload)
    case deleted(RemoteScreenshotDeleteResult)
    case failed(RemoteProtocolError)
}

/// Correlates screenshot replies by request id and reassembles originals into files under
/// `transferDirectory` for one session. A delivered file belongs to the receiver; every other
/// ending deletes it.
///
/// Every registration ends exactly once: with its reply, the Mac's failure, a corrupted
/// transfer (`invalidFrame`), a timeout (`requestTimedOut`), or `CancellationError` when it
/// is superseded by a newer image request, cancelled by its caller, or swept by
/// `finishAll()` (unsubscribe, close, disconnect). Unsolicited replies are dropped.
actor RemoteScreenshotResponses {
    typealias Stream = AsyncThrowingStream<RemoteScreenshotResponse, Swift.Error>

    enum Kind: Equatable, Sendable {
        case thumbnails
        case image(itemID: UUID, revision: Int)
        case delete
    }

    struct Timeouts: Equatable, Sendable {
        /// Thumbnails and delete: time until the single reply arrives.
        var response: Duration
        /// Image: time allowed between the request, the manifest and each chunk.
        var imageInactivity: Duration

        init(response: Duration = .seconds(30), imageInactivity: Duration = .seconds(20)) {
            self.response = response
            self.imageInactivity = imageInactivity
        }
    }

    struct Registration: Sendable {
        let token: UUID
        let stream: Stream

        /// Waits for the reply. A `.failed` reply is thrown; ending without a reply throws `CancellationError`.
        func response() async throws -> RemoteScreenshotResponse {
            for try await response in stream {
                if case let .failed(error) = response { throw error }
                return response
            }
            throw CancellationError()
        }
    }

    static let timedOut = RemoteProtocolError(code: .requestTimedOut, message: "The Mac did not respond in time")
    static let corrupted = RemoteProtocolError(code: .invalidFrame, message: "The screenshot transfer was corrupted")

    private struct Pending {
        let token: UUID
        let kind: Kind
        let continuation: Stream.Continuation
        var assembler: RemoteScreenshotFileAssembler?
        var activity: UInt64 = 0
        var timeout: Task<Void, Never>?
    }

    private let timeouts: Timeouts
    private let transferDirectory: URL
    private var pending: [UUID: Pending] = [:]

    init(
        timeouts: Timeouts = .init(),
        transferDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("OnlyRemoteTransfers", isDirectory: true)
    ) {
        self.timeouts = timeouts
        self.transferDirectory = transferDirectory
    }

    var pendingCount: Int { pending.count }

    func register(_ id: UUID, kind: Kind) -> Registration {
        let (stream, continuation) = Stream.makeStream(of: RemoteScreenshotResponse.self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        finish(id, throwing: CancellationError())
        if case .image = kind {
            // The Mac serves one original at a time and ends a superseded transfer silently.
            for (otherID, entry) in pending {
                if case .image = entry.kind { finish(otherID, throwing: CancellationError()) }
            }
        }
        pending[id] = Pending(token: token, kind: kind, continuation: continuation)
        armTimeout(id)
        continuation.onTermination = { [weak self] _ in Task { await self?.cancel(id, token: token) } }
        return Registration(token: token, stream: stream)
    }

    /// Returns true when the message is a screenshot reply (consumed here, never forwarded as an event).
    func consume(_ message: RemoteMessage) -> Bool {
        switch message {
        case let .screenshotThumbnailsResult(result):
            resolve(result.requestID, expecting: .thumbnails, .thumbnails(result))
        case let .screenshotDeleteResult(result):
            resolve(result.requestID, expecting: .delete, .deleted(result))
        case let .screenshotRequestFailed(failure):
            guard let entry = pending.removeValue(forKey: failure.requestID) else { return true }
            entry.timeout?.cancel()
            entry.assembler?.discard()
            entry.continuation.yield(.failed(failure.error))
            entry.continuation.finish()
        case let .screenshotImageManifest(manifest):
            guard var entry = pending[manifest.requestID] else { return true }
            guard entry.kind == .image(itemID: manifest.itemID, revision: manifest.revision), entry.assembler == nil else {
                finish(manifest.requestID, throwing: Self.corrupted)
                return true
            }
            guard let assembler = try? RemoteScreenshotFileAssembler(manifest: manifest, directory: transferDirectory) else {
                finish(manifest.requestID, throwing: Self.corrupted)
                return true
            }
            entry.assembler = assembler
            pending[manifest.requestID] = entry
            armTimeout(manifest.requestID)
        case let .screenshotImageChunk(chunk):
            guard let assembler = pending[chunk.requestID]?.assembler else {
                finish(chunk.requestID, throwing: Self.corrupted)
                return true
            }
            do {
                try assembler.append(chunk)
                guard assembler.isComplete else {
                    armTimeout(chunk.requestID)
                    return true
                }
                let payload = RemoteScreenshotImagePayload(contentType: assembler.manifest.contentType, fileURL: try assembler.finish())
                guard let entry = pending.removeValue(forKey: chunk.requestID) else { return true }
                entry.timeout?.cancel()
                // A receiver that already went away never reads the file.
                if case .terminated = entry.continuation.yield(.image(payload)) {
                    try? FileManager.default.removeItem(at: payload.fileURL)
                }
                entry.continuation.finish()
            } catch {
                finish(chunk.requestID, throwing: Self.corrupted)
            }
        default:
            return false
        }
        return true
    }

    func cancel(_ id: UUID, token: UUID) {
        guard pending[id]?.token == token else { return }
        finish(id, throwing: CancellationError())
    }

    func finishAll() {
        let values = pending.values
        pending.removeAll()
        for entry in values {
            entry.timeout?.cancel()
            entry.assembler?.discard()
            entry.continuation.finish(throwing: CancellationError())
        }
    }

    private func resolve(_ id: UUID, expecting kind: Kind, _ response: RemoteScreenshotResponse) {
        guard let entry = pending[id] else { return }
        guard entry.kind == kind else {
            finish(id, throwing: Self.corrupted)
            return
        }
        pending.removeValue(forKey: id)
        entry.timeout?.cancel()
        entry.continuation.yield(response)
        entry.continuation.finish()
    }

    private func finish(_ id: UUID, throwing error: Swift.Error) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timeout?.cancel()
        entry.assembler?.discard()
        entry.continuation.finish(throwing: error)
    }

    /// (Re)starts the request's deadline. Image requests restart it on the manifest and every chunk.
    private func armTimeout(_ id: UUID) {
        guard var entry = pending[id] else { return }
        entry.timeout?.cancel()
        entry.activity &+= 1
        let token = entry.token
        let activity = entry.activity
        let duration: Duration
        if case .image = entry.kind { duration = timeouts.imageInactivity } else { duration = timeouts.response }
        entry.timeout = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            await self?.expire(id, token: token, activity: activity)
        }
        pending[id] = entry
    }

    private func expire(_ id: UUID, token: UUID, activity: UInt64) {
        guard let entry = pending[id], entry.token == token, entry.activity == activity else { return }
        finish(id, throwing: Self.timedOut)
    }
}
