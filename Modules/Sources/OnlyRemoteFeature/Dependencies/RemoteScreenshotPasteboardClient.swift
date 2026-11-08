import Dependencies
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Copies a cached original's bytes to the general pasteboard under its own image type (never re-encoded).
struct RemoteScreenshotPasteboardClient: Sendable {
    /// Returns false when the type is not an image or the file cannot be read.
    var copy: @MainActor @Sendable (_ fileURL: URL, _ contentType: String) -> Bool
}

extension RemoteScreenshotPasteboardClient: DependencyKey {
    static let liveValue = Self { url, contentType in
        guard let type = UTType(contentType), type.conforms(to: .image),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        UIPasteboard.general.setItems([[type.identifier: data]])
        return true
    }

    static let testValue = Self { _, _ in false }
}

extension DependencyValues {
    var remoteScreenshotPasteboard: RemoteScreenshotPasteboardClient {
        get { self[RemoteScreenshotPasteboardClient.self] }
        set { self[RemoteScreenshotPasteboardClient.self] = newValue }
    }
}
