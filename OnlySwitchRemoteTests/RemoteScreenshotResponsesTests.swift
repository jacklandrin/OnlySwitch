import Foundation
import RemoteCore
import Testing
@testable import OnlySwitchRemote

@Suite(.timeLimit(.minutes(1)))
struct RemoteScreenshotResponsesTests {
    private let itemID = UUID()

    @Test func thumbnailsResolveTheMatchingRequestAndDropUnsolicitedReplies() async throws {
        let responses = RemoteScreenshotResponses()
        let requestID = UUID()
        let registration = await responses.register(requestID, kind: .thumbnails)
        let thumbnail = try RemoteScreenshotThumbnail(itemID: itemID, revision: 0, jpegData: Data([1]))
        let unsolicited = RemoteScreenshotThumbnailsResult(requestID: UUID(), thumbnails: [], missingIDs: [itemID])
        let expected = RemoteScreenshotThumbnailsResult(requestID: requestID, thumbnails: [thumbnail], missingIDs: [])

        #expect(await responses.consume(.screenshotThumbnailsResult(unsolicited)))
        #expect(await responses.pendingCount == 1)
        #expect(await responses.consume(.screenshotThumbnailsResult(expected)))

        guard case let .thumbnails(result) = try await registration.response() else {
            Issue.record("Expected a thumbnails reply.")
            return
        }
        #expect(result == expected)
        #expect(await responses.pendingCount == 0)
    }

    @Test func nonScreenshotMessagesAreNotConsumed() async {
        let responses = RemoteScreenshotResponses()
        #expect(await responses.consume(.catalogRequest) == false)
        #expect(await responses.consume(.screenshotsLibrary(.init(revision: 1, isCollectionEnabled: true, items: []))) == false)
    }

    @Test func imageChunksAreAssembledAndVerified() async throws {
        let responses = RemoteScreenshotResponses()
        let request = RemoteScreenshotImageRequest(requestID: UUID(), itemID: itemID, revision: 2)
        let registration = await responses.register(request.requestID, kind: .image(itemID: itemID, revision: 2))
        let original = Data((0..<(RemoteScreenshotLimits.maximumChunkBytes * 2 + 5)).map { UInt8(truncatingIfNeeded: $0) })

        for message in try RemoteScreenshotImageEncoder.messages(request: request, contentType: "public.png", data: original) {
            #expect(await responses.consume(message))
        }

        guard case let .image(payload) = try await registration.response() else {
            Issue.record("Expected an image reply.")
            return
        }
        #expect(payload == .init(contentType: "public.png", data: original))
    }

    @Test func tamperedChunkFailsWithInvalidFrame() async throws {
        let responses = RemoteScreenshotResponses()
        let request = RemoteScreenshotImageRequest(requestID: UUID(), itemID: itemID, revision: 0)
        let registration = await responses.register(request.requestID, kind: .image(itemID: itemID, revision: 0))
        let messages = try RemoteScreenshotImageEncoder.messages(request: request, contentType: "public.png", data: Data(repeating: 7, count: 16))
        guard case let .screenshotImageManifest(manifest) = messages.first else {
            Issue.record("Expected a manifest.")
            return
        }
        #expect(await responses.consume(.screenshotImageManifest(manifest)))
        let tampered = try RemoteScreenshotImageChunk(requestID: manifest.requestID, index: 0, data: Data(repeating: 0, count: manifest.byteCount))
        #expect(await responses.consume(.screenshotImageChunk(tampered)))

        let error = await #expect(throws: RemoteProtocolError.self) { _ = try await registration.response() }
        #expect(error?.code == .invalidFrame)
    }

    @Test func manifestForADifferentItemFailsWithInvalidFrame() async throws {
        let responses = RemoteScreenshotResponses()
        let request = RemoteScreenshotImageRequest(requestID: UUID(), itemID: itemID, revision: 0)
        let registration = await responses.register(request.requestID, kind: .image(itemID: itemID, revision: 1))
        let messages = try RemoteScreenshotImageEncoder.messages(request: request, contentType: "public.png", data: Data([1, 2, 3]))
        #expect(await responses.consume(try #require(messages.first)))

        let error = await #expect(throws: RemoteProtocolError.self) { _ = try await registration.response() }
        #expect(error?.code == .invalidFrame)
    }

    @Test func replyOfTheWrongKindFailsWithInvalidFrame() async throws {
        let responses = RemoteScreenshotResponses()
        let requestID = UUID()
        let registration = await responses.register(requestID, kind: .delete)
        #expect(await responses.consume(.screenshotThumbnailsResult(.init(requestID: requestID, thumbnails: [], missingIDs: []))))

        let error = await #expect(throws: RemoteProtocolError.self) { _ = try await registration.response() }
        #expect(error?.code == .invalidFrame)
    }

    @Test func requestFailedResolvesTheMatchingRequestWithItsError() async throws {
        let responses = RemoteScreenshotResponses()
        let requestID = UUID()
        let registration = await responses.register(requestID, kind: .delete)
        let failure = RemoteProtocolError(code: .controlNotFound, message: "Gone")
        #expect(await responses.consume(.screenshotRequestFailed(.init(requestID: requestID, error: failure))))

        let error = await #expect(throws: RemoteProtocolError.self) { _ = try await registration.response() }
        #expect(error == failure)
    }

    @Test func newImageRequestSupersedesThePendingImageRequestOnly() async throws {
        let responses = RemoteScreenshotResponses()
        let first = await responses.register(UUID(), kind: .image(itemID: itemID, revision: 0))
        let thumbnails = await responses.register(UUID(), kind: .thumbnails)
        let second = await responses.register(UUID(), kind: .image(itemID: UUID(), revision: 0))

        await #expect(throws: CancellationError.self) { _ = try await first.response() }
        #expect(await responses.pendingCount == 2)
        await responses.finishAll()
        await #expect(throws: CancellationError.self) { _ = try await thumbnails.response() }
        await #expect(throws: CancellationError.self) { _ = try await second.response() }
    }

    @Test func finishAllFailsEveryPendingRequest() async throws {
        let responses = RemoteScreenshotResponses()
        let registrations = [
            await responses.register(UUID(), kind: .thumbnails),
            await responses.register(UUID(), kind: .image(itemID: itemID, revision: 0)),
            await responses.register(UUID(), kind: .delete),
        ]
        await responses.finishAll()

        for registration in registrations {
            await #expect(throws: CancellationError.self) { _ = try await registration.response() }
        }
        #expect(await responses.pendingCount == 0)
    }

    @Test func unansweredRequestTimesOut() async throws {
        let responses = RemoteScreenshotResponses(timeouts: .init(response: .milliseconds(150), imageInactivity: .seconds(30)))
        let registration = await responses.register(UUID(), kind: .delete)

        let error = await #expect(throws: RemoteProtocolError.self) { _ = try await registration.response() }
        #expect(error?.code == .requestTimedOut)
        #expect(await responses.pendingCount == 0)
    }

    @Test func stalledImageTransferTimesOutAfterInactivity() async throws {
        let responses = RemoteScreenshotResponses(timeouts: .init(response: .seconds(30), imageInactivity: .milliseconds(200)))
        let request = RemoteScreenshotImageRequest(requestID: UUID(), itemID: itemID, revision: 0)
        let registration = await responses.register(request.requestID, kind: .image(itemID: itemID, revision: 0))
        let messages = try RemoteScreenshotImageEncoder.messages(
            request: request,
            contentType: "public.png",
            data: Data(repeating: 1, count: RemoteScreenshotLimits.maximumChunkBytes + 1)
        )
        // Manifest and the first chunk arrive, the last chunk never does.
        for message in messages.dropLast() { #expect(await responses.consume(message)) }

        let error = await #expect(throws: RemoteProtocolError.self) { _ = try await registration.response() }
        #expect(error?.code == .requestTimedOut)
    }

    @Test func everyImageChunkResetsTheInactivityTimeout() async throws {
        let responses = RemoteScreenshotResponses(timeouts: .init(response: .seconds(30), imageInactivity: .milliseconds(400)))
        let request = RemoteScreenshotImageRequest(requestID: UUID(), itemID: itemID, revision: 0)
        let registration = await responses.register(request.requestID, kind: .image(itemID: itemID, revision: 0))
        let original = Data(repeating: 4, count: RemoteScreenshotLimits.maximumChunkBytes * 5 + 1)
        let messages = try RemoteScreenshotImageEncoder.messages(request: request, contentType: "public.png", data: original)
        #expect(messages.count == 7)

        // 7 × 100 ms is longer than the 400 ms inactivity window, but no gap exceeds it.
        for message in messages {
            try await Task.sleep(for: .milliseconds(100))
            #expect(await responses.consume(message))
        }

        guard case let .image(payload) = try await registration.response() else {
            Issue.record("Expected an image reply.")
            return
        }
        #expect(payload.data == original)
    }

    @Test func cancellingTheAwaitingTaskRemovesThePendingRequest() async throws {
        let responses = RemoteScreenshotResponses()
        let registration = await responses.register(UUID(), kind: .image(itemID: itemID, revision: 0))
        let waiter = Task { try await registration.response() }
        await Task.yield()
        waiter.cancel()

        await #expect(throws: CancellationError.self) { _ = try await waiter.value }
        for _ in 0..<100 where await responses.pendingCount > 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await responses.pendingCount == 0)
    }
}
