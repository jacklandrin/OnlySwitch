import Foundation
import RemoteCore
import UniformTypeIdentifiers

/// The image client a `RemoteScreenshotsFeature` reducer runs with, kept in its state so views build
/// drag providers over the reducer's dependencies. A view resolving `@Dependency` itself would see
/// only the app-wide values, never reducer-scoped overrides such as the review demo's.
/// It is a dependency handle, not data, so it never takes part in equality.
struct RemoteScreenshotDragImages: Equatable, Sendable {
    var client: RemoteScreenshotImageClient = .unavailable

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// Builds drag item providers for screenshots. It only bridges to the image client: no reducer
/// state is read or changed, and a cancelled or superseded load simply fails the drop.
enum RemoteScreenshotDragProvider {
    /// Registers the original as a file of its own type. The file is resolved only when a drop target
    /// asks for it: the cached original when one is known, otherwise the image client, which is
    /// cache-first and shares a single download per Mac + item + revision.
    ///
    /// The provider is not open-in-place, so the system copies the file for the receiver before the
    /// completion returns. The cached file already carries the sanitized display name; only when it
    /// does not is a temporary copy with that name handed out (and removed afterwards).
    static func itemProvider(
        macID: UUID,
        item: RemoteScreenshotItem,
        cachedURL: URL?,
        images: RemoteScreenshotImageClient
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = (item.fileName as NSString).deletingPathExtension
        let type = UTType(item.contentType).flatMap { $0.conforms(to: .image) ? $0 : nil } ?? .image
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            let task = Task {
                do {
                    let url: URL
                    if let cachedURL, FileManager.default.fileExists(atPath: cachedURL.path) {
                        url = cachedURL
                    } else {
                        url = try await images.load(macID, item)
                    }
                    try Task.checkCancellation()
                    progress.completedUnitCount = 1
                    try handOver(url, fileName: item.fileName, to: completion)
                } catch {
                    completion(nil, false, error)
                }
            }
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
        return provider
    }

    private static func handOver(
        _ url: URL,
        fileName: String,
        to completion: @Sendable (URL?, Bool, (any Error)?) -> Void
    ) throws {
        guard fileName.isEmpty == false, url.lastPathComponent != fileName else {
            completion(url, false, nil)
            return
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnlyRemoteDrag", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent(fileName, isDirectory: false)
        try FileManager.default.copyItem(at: url, to: copy)
        completion(copy, false, nil)
    }
}
