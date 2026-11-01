import CryptoKit
import Foundation
import Testing
@testable import RemoteCore

struct RemoteScreenshotsContractTests {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!

    @Test func protocolOneNineEnablesScreenshots() {
        #expect(RemoteProtocolVersion.current == .init(major: 1, minor: 9))
        #expect(RemoteProtocolVersion(major: 1, minor: 9).supportsScreenshotsRemote)
        #expect(RemoteProtocolVersion(major: 1, minor: 8).supportsScreenshotsRemote == false)
    }

    @Test func fileNamesAreSanitizedDisplayNames() {
        #expect(RemoteScreenshotItem.sanitizedFileName("../a/b:c.png") == "abc.png")
        #expect(RemoteScreenshotItem.sanitizedFileName("..hidden.png") == "hidden.png")
        #expect(RemoteScreenshotItem.sanitizedFileName("a/b.png") == "ab.png")
        #expect(RemoteScreenshotItem.sanitizedFileName("x\u{0}y.png") == "xy.png")
        #expect(RemoteScreenshotItem.sanitizedFileName("   ") == "Screenshot")
        #expect(RemoteScreenshotItem.sanitizedFileName(String(repeating: "x", count: 500)).count == 120)
    }

    @Test func itemDecodingSanitizesAndClamps() throws {
        let json = #"{"id":"\#(id.uuidString)","fileName":"../evil.png","contentType":"public.png","createdAt":0,"isPinned":false,"revision":-4,"byteCount":-1}"#
        let item = try JSONDecoder().decode(RemoteScreenshotItem.self, from: Data(json.utf8))
        #expect(item.fileName == "evil.png")
        #expect(item.revision == 0)
        #expect(item.byteCount == 0)
        #expect(item.cacheKey == "\(id.uuidString.lowercased())-0")
    }

    @Test func libraryDeduplicatesAndCapsItems() throws {
        let item = RemoteScreenshotItem(id: id, fileName: "a.png", contentType: "public.png", createdAt: .init(timeIntervalSince1970: 0), isPinned: false, revision: 0, byteCount: 1)
        let many = (0..<600).map { index in
            RemoteScreenshotItem(id: UUID(), fileName: "\(index).png", contentType: "public.png", createdAt: .init(timeIntervalSince1970: 0), isPinned: false, revision: 0, byteCount: 1)
        }
        #expect(RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: [item, item]).items.count == 1)
        let capped = RemoteScreenshotLibrary(revision: 1, isCollectionEnabled: true, items: many)
        #expect(capped.items.count == RemoteScreenshotLimits.maximumItems)
        let decoded = try JSONDecoder().decode(RemoteScreenshotLibrary.self, from: JSONEncoder().encode(capped))
        #expect(decoded == capped)
    }

    @Test func requestsCapIDs() {
        let ids = (0..<40).map { _ in UUID() }
        #expect(RemoteScreenshotThumbnailsRequest(requestID: UUID(), ids: ids + ids).ids.count == 12)
        #expect(RemoteScreenshotDeleteRequest(requestID: UUID(), ids: (0..<200).map { _ in UUID() }).ids.count == 100)
    }

    @Test func thumbnailRejectsEmptyOrOversizedData() {
        #expect(throws: RemoteScreenshotValidationError.invalidThumbnail) { try RemoteScreenshotThumbnail(itemID: id, revision: 0, jpegData: Data()) }
        #expect(throws: RemoteScreenshotValidationError.invalidThumbnail) {
            try RemoteScreenshotThumbnail(itemID: id, revision: 0, jpegData: Data(count: RemoteScreenshotLimits.maximumThumbnailBytes + 1))
        }
    }

    @Test func encoderAndAssemblerRoundTripAndVerifyDigest() throws {
        let data = Data((0..<(RemoteScreenshotLimits.maximumChunkBytes * 2 + 17)).map { UInt8($0 % 251) })
        let request = RemoteScreenshotImageRequest(requestID: UUID(), itemID: id, revision: 3)
        let messages = try RemoteScreenshotImageEncoder.messages(request: request, contentType: "public.png", data: data)
        #expect(messages.count == 4)
        guard case let .screenshotImageManifest(manifest) = messages[0] else { Issue.record("manifest first"); return }
        #expect(manifest.chunkCount == 3)
        #expect(manifest.sha256 == Data(SHA256.hash(data: data)))
        var assembler = RemoteScreenshotImageAssembler(manifest: manifest)
        for case let .screenshotImageChunk(chunk) in messages.dropFirst() { try assembler.append(chunk) }
        #expect(assembler.isComplete)
        #expect(try assembler.data() == data)
        // Round-trip through the wire enum.
        for message in messages {
            #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
        }
    }

    @Test func assemblerRejectsOutOfOrderForeignAndTamperedChunks() throws {
        let data = Data(repeating: 7, count: RemoteScreenshotLimits.maximumChunkBytes + 1)
        let request = RemoteScreenshotImageRequest(requestID: UUID(), itemID: id, revision: 0)
        let messages = try RemoteScreenshotImageEncoder.messages(request: request, contentType: "public.png", data: data)
        guard case let .screenshotImageManifest(manifest) = messages[0],
              case let .screenshotImageChunk(first) = messages[1],
              case let .screenshotImageChunk(second) = messages[2] else { Issue.record("shape"); return }

        var outOfOrder = RemoteScreenshotImageAssembler(manifest: manifest)
        #expect(throws: RemoteScreenshotValidationError.invalidChunk) { try outOfOrder.append(second) }

        var foreign = RemoteScreenshotImageAssembler(manifest: manifest)
        let other = try RemoteScreenshotImageChunk(requestID: UUID(), index: 0, data: first.data)
        #expect(throws: RemoteScreenshotValidationError.invalidChunk) { try foreign.append(other) }

        var tampered = RemoteScreenshotImageAssembler(manifest: manifest)
        try tampered.append(first)
        try tampered.append(try RemoteScreenshotImageChunk(requestID: request.requestID, index: 1, data: Data([8])))
        #expect(throws: RemoteScreenshotValidationError.digestMismatch) { try tampered.data() }

        var incomplete = RemoteScreenshotImageAssembler(manifest: manifest)
        try incomplete.append(first)
        #expect(throws: RemoteScreenshotValidationError.incomplete) { try incomplete.data() }
    }

    @Test func manifestRejectsInconsistentOrOversizedImages() {
        #expect(throws: RemoteScreenshotValidationError.imageTooLarge) {
            try RemoteScreenshotImageManifest(requestID: UUID(), itemID: id, revision: 0, contentType: "public.png", byteCount: RemoteScreenshotLimits.maximumImageBytes + 1, chunkCount: 193, sha256: Data(count: 32))
        }
        #expect(throws: RemoteScreenshotValidationError.invalidManifest) {
            try RemoteScreenshotImageManifest(requestID: UUID(), itemID: id, revision: 0, contentType: "public.png", byteCount: 10, chunkCount: 2, sha256: Data(count: 32))
        }
        #expect(throws: RemoteScreenshotValidationError.invalidManifest) {
            try RemoteScreenshotImageManifest(requestID: UUID(), itemID: id, revision: 0, contentType: "public.png", byteCount: 10, chunkCount: 1, sha256: Data(count: 31))
        }
    }

    @Test func newMessagesRoundTrip() throws {
        let item = RemoteScreenshotItem(id: id, fileName: "a.png", contentType: "public.png", createdAt: .init(timeIntervalSince1970: 10), isPinned: true, revision: 2, byteCount: 3)
        let messages: [RemoteMessage] = [
            .screenshotsSubscriptionUpdate(true),
            .screenshotsLibrary(.init(revision: 4, isCollectionEnabled: false, items: [item])),
            .screenshotThumbnailsRequest(.init(requestID: id, ids: [id])),
            .screenshotThumbnailsResult(.init(requestID: id, thumbnails: [try .init(itemID: id, revision: 2, jpegData: Data([1]))], missingIDs: [])),
            .screenshotImageRequest(.init(requestID: id, itemID: id, revision: 2)),
            .screenshotDeleteRequest(.init(requestID: id, ids: [id])),
            .screenshotDeleteResult(.init(requestID: id, failedIDs: [id])),
            .screenshotRequestFailed(.init(requestID: id, error: .init(code: .controlNotFound, message: "gone"))),
        ]
        for message in messages {
            #expect(try JSONDecoder().decode(RemoteMessage.self, from: JSONEncoder().encode(message)) == message)
        }
    }
}
