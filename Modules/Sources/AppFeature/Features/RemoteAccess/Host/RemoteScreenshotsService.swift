import Foundation
import RemoteCore

/// Screenshot effects a remote session may perform. Items are addressed by recorded id and revision only.
struct RemoteScreenshotsService: Sendable {
    /// Recordings are listed only when `includesRecordings` (peer protocol 1.10+).
    var libraries: @Sendable (_ includesRecordings: Bool) -> AsyncStream<RemoteScreenshotLibrary>
    var thumbnails: @Sendable ([UUID]) async -> (thumbnails: [RemoteScreenshotThumbnail], missingIDs: [UUID])
    /// Returns memory-mapped original bytes; recordings only when `includesRecordings`.
    var image: @Sendable (_ itemID: UUID, _ revision: Int, _ includesRecordings: Bool) async throws(RemoteProtocolError) -> (contentType: String, data: Data)
    /// Returns the ids that could not be moved to the Trash.
    var delete: @Sendable ([UUID]) async -> [UUID]

    static let unavailable = Self(
        libraries: { _ in AsyncStream { $0.finish() } },
        thumbnails: { (thumbnails: [], missingIDs: $0) },
        image: { _, _, _ async throws(RemoteProtocolError) in
            throw RemoteProtocolError(code: .actionNotSupported, message: "Screenshots are unavailable")
        },
        delete: { $0 }
    )
}
