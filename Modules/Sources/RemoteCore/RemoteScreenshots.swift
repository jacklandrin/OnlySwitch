import CryptoKit
import Foundation

public enum RemoteScreenshotLimits {
    public static let maximumItems = 500
    public static let maximumFileNameCharacters = 120
    public static let maximumThumbnailBytes = 65_536
    public static let maximumThumbnailPixel = 480
    public static let maximumThumbnailsPerRequest = 12
    public static let maximumImageBytes = 48 * 1_048_576
    public static let maximumChunkBytes = 262_144
    public static let maximumDeleteCount = 100
}

public enum RemoteScreenshotValidationError: Error, Equatable, Sendable {
    case invalidThumbnail, invalidManifest, invalidChunk, imageTooLarge, digestMismatch, incomplete
}

public struct RemoteScreenshotItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Sanitized display name, used only for drag/drop and copy metadata; never a path.
    public let fileName: String
    /// Uniform Type Identifier of the original, e.g. `public.png`.
    public let contentType: String
    public let createdAt: Date
    public let isPinned: Bool
    /// Bumped by the Mac editor; invalidates cached thumbnails and originals.
    public let revision: Int
    public let byteCount: Int

    public init(id: UUID, fileName: String, contentType: String, createdAt: Date, isPinned: Bool, revision: Int, byteCount: Int) {
        self.id = id
        self.fileName = Self.sanitizedFileName(fileName)
        self.contentType = String(contentType.prefix(128))
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.revision = max(0, revision)
        self.byteCount = max(0, byteCount)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            fileName: try values.decode(String.self, forKey: .fileName),
            contentType: try values.decode(String.self, forKey: .contentType),
            createdAt: try values.decode(Date.self, forKey: .createdAt),
            isPinned: try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            revision: try values.decode(Int.self, forKey: .revision),
            byteCount: try values.decode(Int.self, forKey: .byteCount)
        )
    }

    public var cacheKey: String { "\(id.uuidString.lowercased())-\(revision)" }

    public static func sanitizedFileName(_ name: String) -> String {
        let scalars = name.unicodeScalars.filter {
            CharacterSet.controlCharacters.contains($0) == false && $0 != "/" && $0 != ":"
        }
        var result = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix(".") { result.removeFirst() }
        result = String(result.prefix(RemoteScreenshotLimits.maximumFileNameCharacters))
        return result.isEmpty ? "Screenshot" : result
    }
}

public struct RemoteScreenshotLibrary: Codable, Equatable, Sendable {
    public let revision: UInt64
    /// Whether the Mac currently collects new captures; drives the empty-state hint.
    public let isCollectionEnabled: Bool
    /// In the Mac's display order (pinned first, newest first).
    public let items: [RemoteScreenshotItem]

    public init(revision: UInt64, isCollectionEnabled: Bool, items: [RemoteScreenshotItem]) {
        var seen = Set<UUID>()
        self.revision = revision
        self.isCollectionEnabled = isCollectionEnabled
        self.items = Array(items.filter { seen.insert($0.id).inserted }.prefix(RemoteScreenshotLimits.maximumItems))
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            revision: try values.decode(UInt64.self, forKey: .revision),
            isCollectionEnabled: try values.decodeIfPresent(Bool.self, forKey: .isCollectionEnabled) ?? true,
            items: try values.decode([RemoteScreenshotItem].self, forKey: .items)
        )
    }
}

public struct RemoteScreenshotThumbnailsRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let ids: [UUID]

    public init(requestID: UUID, ids: [UUID]) {
        var seen = Set<UUID>()
        self.requestID = requestID
        self.ids = Array(ids.filter { seen.insert($0).inserted }.prefix(RemoteScreenshotLimits.maximumThumbnailsPerRequest))
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(requestID: try values.decode(UUID.self, forKey: .requestID), ids: try values.decode([UUID].self, forKey: .ids))
    }
}

public struct RemoteScreenshotThumbnail: Codable, Equatable, Sendable {
    public let itemID: UUID
    public let revision: Int
    public let jpegData: Data

    public init(itemID: UUID, revision: Int, jpegData: Data) throws {
        guard jpegData.isEmpty == false, jpegData.count <= RemoteScreenshotLimits.maximumThumbnailBytes else {
            throw RemoteScreenshotValidationError.invalidThumbnail
        }
        self.itemID = itemID
        self.revision = max(0, revision)
        self.jpegData = jpegData
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(itemID: values.decode(UUID.self, forKey: .itemID), revision: values.decode(Int.self, forKey: .revision), jpegData: values.decode(Data.self, forKey: .jpegData))
    }
}

public struct RemoteScreenshotThumbnailsResult: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let thumbnails: [RemoteScreenshotThumbnail]
    public let missingIDs: [UUID]

    public init(requestID: UUID, thumbnails: [RemoteScreenshotThumbnail], missingIDs: [UUID]) {
        self.requestID = requestID
        self.thumbnails = Array(thumbnails.prefix(RemoteScreenshotLimits.maximumThumbnailsPerRequest))
        self.missingIDs = Array(missingIDs.prefix(RemoteScreenshotLimits.maximumThumbnailsPerRequest))
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            requestID: try values.decode(UUID.self, forKey: .requestID),
            thumbnails: try values.decode([RemoteScreenshotThumbnail].self, forKey: .thumbnails),
            missingIDs: try values.decodeIfPresent([UUID].self, forKey: .missingIDs) ?? []
        )
    }
}

public struct RemoteScreenshotImageRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let itemID: UUID
    public let revision: Int

    public init(requestID: UUID, itemID: UUID, revision: Int) {
        self.requestID = requestID
        self.itemID = itemID
        self.revision = revision
    }
}

public struct RemoteScreenshotImageManifest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let itemID: UUID
    public let revision: Int
    public let contentType: String
    public let byteCount: Int
    public let chunkCount: Int
    public let sha256: Data

    public init(requestID: UUID, itemID: UUID, revision: Int, contentType: String, byteCount: Int, chunkCount: Int, sha256: Data) throws {
        guard byteCount <= RemoteScreenshotLimits.maximumImageBytes else { throw RemoteScreenshotValidationError.imageTooLarge }
        let chunkBytes = RemoteScreenshotLimits.maximumChunkBytes
        guard byteCount > 0,
              chunkCount == (byteCount + chunkBytes - 1) / chunkBytes,
              sha256.count == 32,
              contentType.isEmpty == false, contentType.utf8.count <= 128 else {
            throw RemoteScreenshotValidationError.invalidManifest
        }
        self.requestID = requestID
        self.itemID = itemID
        self.revision = revision
        self.contentType = contentType
        self.byteCount = byteCount
        self.chunkCount = chunkCount
        self.sha256 = sha256
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            requestID: values.decode(UUID.self, forKey: .requestID),
            itemID: values.decode(UUID.self, forKey: .itemID),
            revision: values.decode(Int.self, forKey: .revision),
            contentType: values.decode(String.self, forKey: .contentType),
            byteCount: values.decode(Int.self, forKey: .byteCount),
            chunkCount: values.decode(Int.self, forKey: .chunkCount),
            sha256: values.decode(Data.self, forKey: .sha256)
        )
    }
}

public struct RemoteScreenshotImageChunk: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let index: Int
    public let data: Data

    public init(requestID: UUID, index: Int, data: Data) throws {
        guard index >= 0, data.isEmpty == false, data.count <= RemoteScreenshotLimits.maximumChunkBytes else {
            throw RemoteScreenshotValidationError.invalidChunk
        }
        self.requestID = requestID
        self.index = index
        self.data = data
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(requestID: values.decode(UUID.self, forKey: .requestID), index: values.decode(Int.self, forKey: .index), data: values.decode(Data.self, forKey: .data))
    }
}

public struct RemoteScreenshotDeleteRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let ids: [UUID]

    public init(requestID: UUID, ids: [UUID]) {
        var seen = Set<UUID>()
        self.requestID = requestID
        self.ids = Array(ids.filter { seen.insert($0).inserted }.prefix(RemoteScreenshotLimits.maximumDeleteCount))
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(requestID: try values.decode(UUID.self, forKey: .requestID), ids: try values.decode([UUID].self, forKey: .ids))
    }
}

public struct RemoteScreenshotDeleteResult: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let failedIDs: [UUID]

    public init(requestID: UUID, failedIDs: [UUID]) {
        self.requestID = requestID
        self.failedIDs = Array(failedIDs.prefix(RemoteScreenshotLimits.maximumDeleteCount))
    }
}

public struct RemoteScreenshotRequestFailure: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let error: RemoteProtocolError

    public init(requestID: UUID, error: RemoteProtocolError) {
        self.requestID = requestID
        self.error = error
    }
}

public enum RemoteScreenshotImageEncoder {
    /// A manifest followed by contiguous chunks. Throws for empty or oversized data.
    public static func messages(request: RemoteScreenshotImageRequest, contentType: String, data: Data) throws -> [RemoteMessage] {
        let chunkBytes = RemoteScreenshotLimits.maximumChunkBytes
        let manifest = try RemoteScreenshotImageManifest(
            requestID: request.requestID,
            itemID: request.itemID,
            revision: request.revision,
            contentType: contentType,
            byteCount: data.count,
            chunkCount: (data.count + chunkBytes - 1) / chunkBytes,
            sha256: Data(SHA256.hash(data: data))
        )
        var messages: [RemoteMessage] = [.screenshotImageManifest(manifest)]
        var offset = data.startIndex
        var index = 0
        while offset < data.endIndex {
            let end = data.index(offset, offsetBy: chunkBytes, limitedBy: data.endIndex) ?? data.endIndex
            messages.append(.screenshotImageChunk(try .init(requestID: request.requestID, index: index, data: Data(data[offset..<end]))))
            offset = end
            index += 1
        }
        return messages
    }
}

/// Reassembles one original. Chunks must arrive in order (the transport is ordered).
public struct RemoteScreenshotImageAssembler: Sendable {
    public let manifest: RemoteScreenshotImageManifest
    private var bytes = Data()
    private var nextIndex = 0

    public init(manifest: RemoteScreenshotImageManifest) {
        self.manifest = manifest
        bytes.reserveCapacity(manifest.byteCount)
    }

    public var isComplete: Bool { nextIndex == manifest.chunkCount }

    public mutating func append(_ chunk: RemoteScreenshotImageChunk) throws {
        guard chunk.requestID == manifest.requestID,
              chunk.index == nextIndex,
              nextIndex < manifest.chunkCount,
              bytes.count + chunk.data.count <= manifest.byteCount else {
            throw RemoteScreenshotValidationError.invalidChunk
        }
        bytes.append(chunk.data)
        nextIndex += 1
    }

    public func data() throws -> Data {
        guard isComplete, bytes.count == manifest.byteCount else { throw RemoteScreenshotValidationError.incomplete }
        guard Data(SHA256.hash(data: bytes)) == manifest.sha256 else { throw RemoteScreenshotValidationError.digestMismatch }
        return bytes
    }
}
