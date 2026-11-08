#if os(macOS)
import Foundation
import UniformTypeIdentifiers

public struct ScreenshotItem: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    /// Relative to the library folder; never absolute.
    public var fileName: String
    public var createdAt: Date
    public var isPinned: Bool
    /// Bumped after an edit; used as the thumbnail cache key.
    public var revision: Int
    public init(id: UUID, fileName: String, createdAt: Date, isPinned: Bool = false, revision: Int = 0) { self.id = id; self.fileName = fileName; self.createdAt = createdAt; self.isPinned = isPinned; self.revision = revision }
}
public enum ScreenshotMediaType: Equatable, Sendable {
    case image, recording
    /// nil for hidden names and anything that is neither an image nor a movie.
    public init?(fileName: String) {
        guard !fileName.hasPrefix("."), let type = UTType(filenameExtension: (fileName as NSString).pathExtension) else { return nil }
        if type.conforms(to: .image) { self = .image } else if type.conforms(to: .movie) { self = .recording } else { return nil }
    }
}

public extension ScreenshotItem {
    /// Derived from the extension so the manifest format is unchanged.
    var mediaType: ScreenshotMediaType { ScreenshotMediaType(fileName: fileName) ?? .image }
    var isRecording: Bool { mediaType == .recording }
}
public struct ScreenshotFailure: Error, Equatable, Sendable {
    public var key: String
    public var itemID: UUID?
    public init(key: String, itemID: UUID? = nil) { self.key = key; self.itemID = itemID }
}
public extension ScreenshotFailure {
    static let trashFailedKey = "Screenshot Trash Failed"
    static let captureSettingsFailedKey = "Screenshot Capture Settings Failed"
    static let libraryFailedKey = "Screenshot Library Failed"
    static let notFoundKey = "Screenshot Not Found"
    static let copyFailedKey = "Screenshot Copy Failed"
    static let saveFailedKey = "Screenshot Save Failed"
}
public struct ScreenshotCaptureSettings: Equatable, Sendable, Codable {
    /// nil = key absent (system default ~/Desktop).
    public var location: String?
    /// macOS 27 and later use a separate still-image destination.
    public var screenshotLocation: String?
    /// nil = key absent (system default true).
    public var showThumbnail: Bool?
    /// nil identifies backups made before the still-image destination was tracked.
    public var screenshotLocationBackedUp: Bool?
    /// macOS 27 and later use a separate recording destination.
    public var screenRecordingLocation: String?
    /// nil identifies backups made before the recording destination was tracked.
    public var screenRecordingLocationBackedUp: Bool?
    public init(location: String? = nil, screenshotLocation: String? = nil, showThumbnail: Bool? = nil, screenshotLocationBackedUp: Bool? = true, screenRecordingLocation: String? = nil, screenRecordingLocationBackedUp: Bool? = true) {
        self.location = location
        self.screenshotLocation = screenshotLocation
        self.showThumbnail = showThumbnail
        self.screenshotLocationBackedUp = screenshotLocationBackedUp
        self.screenRecordingLocation = screenRecordingLocation
        self.screenRecordingLocationBackedUp = screenRecordingLocationBackedUp
    }
}
public enum ScreenshotCaptureStatus: Equatable, Sendable { case disabled, active, changedElsewhere }

extension Array where Element == ScreenshotItem {
    /// Pinned first, then newest first; stable by id.
    public func displayOrdered() -> [ScreenshotItem] {
        sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
#endif
