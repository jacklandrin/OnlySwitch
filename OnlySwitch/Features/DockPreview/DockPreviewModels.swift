import CoreGraphics
import Foundation

struct DockPreviewAuthorization: Equatable, Sendable {
    var accessibility: Bool
    var screenRecording: Bool

    static let unknown = Self(accessibility: false, screenRecording: false)
    static let authorized = Self(accessibility: true, screenRecording: true)

    var isAuthorized: Bool { accessibility && screenRecording }
}

struct DockHoverEvent: Equatable, Sendable {
    var pid: pid_t
    var appName: String
    var itemFrame: CGRect
    var screenFrame: CGRect
}

struct DockPreviewWindow: Equatable, Identifiable, Sendable {
    var id: CGWindowID
    var title: String
    var pid: pid_t
    var frame: CGRect
    var isActivatable: Bool
    var thumbnailData: Data?
}

