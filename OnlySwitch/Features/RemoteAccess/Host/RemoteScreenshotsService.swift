import Foundation
import RemoteCore

/// Screenshot effects a remote session may perform. Items are addressed by recorded id and revision only.
struct RemoteScreenshotsService: Sendable {
    var libraries: @Sendable () -> AsyncStream<RemoteScreenshotLibrary>
    var thumbnails: @Sendable ([UUID]) async -> (thumbnails: [RemoteScreenshotThumbnail], missingIDs: [UUID])
    var image: @Sendable (_ itemID: UUID, _ revision: Int) async throws(RemoteProtocolError) -> (contentType: String, data: Data)
    /// Returns the ids that could not be moved to the Trash.
    var delete: @Sendable ([UUID]) async -> [UUID]

    static let unavailable = Self(
        libraries: { AsyncStream { $0.finish() } },
        thumbnails: { (thumbnails: [], missingIDs: $0) },
        image: { _, _ async throws(RemoteProtocolError) in
            throw RemoteProtocolError(code: .actionNotSupported, message: "Screenshots are unavailable")
        },
        delete: { $0 }
    )
}
