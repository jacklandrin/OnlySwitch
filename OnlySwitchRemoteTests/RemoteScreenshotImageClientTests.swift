import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@Suite(.timeLimit(.minutes(1)))
struct RemoteScreenshotImageClientTests {
    private let macID = UUID(uuidString: "00000000-0000-0000-0000-00000000E001")!
    private let requestID = UUID(uuidString: "00000000-0000-0000-0000-00000000E0FF")!

    private func item(_ n: Int = 1, revision: Int = 0) -> RemoteScreenshotItem {
        .init(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, fileName: "Shot.png", contentType: "public.png", createdAt: .init(timeIntervalSince1970: Double(n)), isPinned: false, revision: revision, byteCount: 3)
    }

    private func key(_ item: RemoteScreenshotItem) -> RemoteScreenshotImageLoads.Key {
        .init(macID: macID, itemID: item.id, revision: item.revision)
    }

    // MARK: - Client

    @Test func cachedOriginalIsReturnedWithoutDownloading() async throws {
        let cache = RemoteScreenshotCacheClient.live(root: try Self.root())
        let shot = item()
        let cached = try await cache.saveImage(macID, shot, Data([7]))
        let fetches = FetchRecorder()
        let client = RemoteScreenshotImageClient.live(
            cache: cache,
            fetchImage: { await fetches.fetch($0) },
            makeRequestID: { requestID }
        )

        #expect(try await client.load(macID, shot) == cached)
        #expect(await fetches.invocations.isEmpty)
    }

    @Test func missingOriginalIsDownloadedForItsRevisionAndCached() async throws {
        let cache = RemoteScreenshotCacheClient.live(root: try Self.root())
        let shot = item(revision: 3)
        let fetches = FetchRecorder()
        let client = RemoteScreenshotImageClient.live(
            cache: cache,
            fetchImage: { await fetches.fetch($0) },
            makeRequestID: { requestID }
        )

        let url = try await client.load(macID, shot)

        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        #expect(await cache.imageURL(macID, shot) == url)
        #expect(await fetches.invocations == [
            .init(macID: macID, request: .init(requestID: requestID, itemID: shot.id, revision: 3)),
        ])
        _ = try await client.load(macID, shot)
        #expect(await fetches.invocations.count == 1)
    }

    @Test func downloadCancellationPropagatesUnchanged() async throws {
        let client = RemoteScreenshotImageClient.live(
            cache: RemoteScreenshotCacheClient.live(root: try Self.root()),
            fetchImage: { _ in throw CancellationError() },
            makeRequestID: { requestID }
        )

        await #expect(throws: CancellationError.self) { try await client.load(macID, item()) }
    }

    // MARK: - Single flight

    @Test func concurrentLoadsOfTheSameRevisionShareOneDownload() async throws {
        let loads = RemoteScreenshotImageLoads()
        let gate = DownloadGate()
        let shot = item()
        let first = Task { try await loads.load(key(shot)) { try await gate.download() } }
        let second = Task { try await loads.load(key(shot)) { try await gate.download() } }
        await waitUntil {
            let waiters = await loads.waiterCount(for: key(shot))
            let downloads = await gate.pendingCount
            return waiters == 2 && downloads == 1
        }

        await gate.succeed(Self.url)

        #expect(try await first.value == Self.url)
        #expect(try await second.value == Self.url)
        #expect(await gate.started == 1)
        #expect(await loads.waiterCount(for: key(shot)) == 0)
    }

    @Test func differentRevisionsDownloadSeparately() async throws {
        let loads = RemoteScreenshotImageLoads()
        let gate = DownloadGate()
        let old = item(revision: 0), new = item(revision: 1)
        let first = Task { try await loads.load(key(old)) { try await gate.download() } }
        let second = Task { try await loads.load(key(new)) { try await gate.download() } }
        await waitUntil { await gate.pendingCount == 2 }

        await gate.succeed(Self.url)

        _ = try await first.value
        _ = try await second.value
        #expect(await gate.started == 2)
    }

    @Test func cancellingOneWaiterKeepsTheSharedDownloadForTheOthers() async throws {
        let loads = RemoteScreenshotImageLoads()
        let gate = DownloadGate()
        let shot = item()
        let first = Task { try await loads.load(key(shot)) { try await gate.download() } }
        let second = Task { try await loads.load(key(shot)) { try await gate.download() } }
        await waitUntil {
            let waiters = await loads.waiterCount(for: key(shot))
            let downloads = await gate.pendingCount
            return waiters == 2 && downloads == 1
        }

        first.cancel()

        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await loads.waiterCount(for: key(shot)) == 1)
        #expect(await gate.cancelled == 0)
        await gate.succeed(Self.url)
        #expect(try await second.value == Self.url)
        #expect(await gate.started == 1)
    }

    @Test func cancellingTheLastWaiterCancelsTheDownloadAndAllowsARetry() async throws {
        let loads = RemoteScreenshotImageLoads()
        let gate = DownloadGate()
        let shot = item()
        let first = Task { try await loads.load(key(shot)) { try await gate.download() } }
        await waitUntil { await gate.pendingCount == 1 }

        first.cancel()

        await #expect(throws: CancellationError.self) { try await first.value }
        await waitUntil { await gate.cancelled == 1 }
        #expect(await loads.waiterCount(for: key(shot)) == 0)

        let retry = Task { try await loads.load(key(shot)) { try await gate.download() } }
        await waitUntil { await gate.pendingCount == 1 }
        await gate.succeed(Self.url)
        #expect(try await retry.value == Self.url)
        #expect(await gate.started == 2)
    }

    @Test func alreadyCancelledCallerFailsWithoutStartingADownload() async throws {
        let loads = RemoteScreenshotImageLoads()
        let gate = DownloadGate()
        let shot = item()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loads.load(key(shot)) { try await gate.download() }
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await loads.waiterCount(for: key(shot)) == 0)
    }

    @Test func sharedFailuresReachEveryWaiterUnchangedAndAreNotRemembered() async throws {
        let loads = RemoteScreenshotImageLoads()
        let gate = DownloadGate()
        let shot = item()
        let first = Task { try await loads.load(key(shot)) { try await gate.download() } }
        let second = Task { try await loads.load(key(shot)) { try await gate.download() } }
        await waitUntil {
            let waiters = await loads.waiterCount(for: key(shot))
            let downloads = await gate.pendingCount
            return waiters == 2 && downloads == 1
        }

        await gate.fail(CancellationError())

        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: CancellationError.self) { try await second.value }

        let retry = Task { try await loads.load(key(shot)) { try await gate.download() } }
        await waitUntil { await gate.pendingCount == 1 }
        let failure = RemoteProtocolError(code: .requestTimedOut, message: "late")
        await gate.fail(failure)
        await #expect(throws: failure) { try await retry.value }
        #expect(await gate.started == 2)
    }

    // MARK: - Helpers

    private static let url = URL(fileURLWithPath: "/tmp/shot.png")

    private static func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteScreenshotImages-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async {
        while await condition() == false { await Task.yield() }
    }
}

private actor FetchRecorder {
    private(set) var invocations: [RemoteScreenshotInvocation<RemoteScreenshotImageRequest>] = []

    func fetch(_ invocation: RemoteScreenshotInvocation<RemoteScreenshotImageRequest>) -> RemoteScreenshotImagePayload {
        invocations.append(invocation)
        return .init(contentType: "public.png", data: Data([1, 2, 3]))
    }
}

/// A download the test resolves by hand; observes cancellation of the download task.
private actor DownloadGate {
    private(set) var started = 0
    private(set) var cancelled = 0
    private var pending: [UUID: CheckedContinuation<URL, any Error>] = [:]

    var pendingCount: Int { pending.count }

    func download() async throws -> URL {
        started += 1
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    cancelled += 1
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func succeed(_ url: URL) {
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(returning: url) }
    }

    func fail(_ error: any Error) {
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    private func cancel(_ id: UUID) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        cancelled += 1
        continuation.resume(throwing: CancellationError())
    }
}
