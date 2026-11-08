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
    var mediaPlayer: DockPreviewMediaPlayer? = nil
}

enum DockPreviewMediaPlayer: Equatable, Sendable {
    case appleMusic
    case spotify

    init?(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.apple.Music": self = .appleMusic
        case "com.spotify.client": self = .spotify
        default: return nil
        }
    }
}

enum DockPreviewMediaCommand: Equatable, Sendable {
    case previousTrack
    case playPause
    case nextTrack
}

// At the observer's 80 ms interval, three equal direct hits avoid anchoring
// the first preview to a frame sampled during Dock reveal or magnification.
struct DockHoverStabilizer: Sendable {
    enum Update: Equatable {
        case unchanged
        case changed(DockHoverEvent?)
    }

    private var candidate: DockHoverEvent?
    private var candidateCount = 0
    private var emitted: DockHoverEvent?

    mutating func update(
        _ event: DockHoverEvent?,
        isDirectHit: Bool = true
    ) -> Update {
        guard let event else {
            candidate = nil
            candidateCount = 0
            guard emitted != nil else { return .unchanged }
            emitted = nil
            return .changed(nil)
        }

        guard isDirectHit else {
            candidate = nil
            candidateCount = 0
            return .unchanged
        }

        guard event != emitted else {
            candidate = nil
            candidateCount = 0
            return .unchanged
        }

        if candidate == event {
            candidateCount += 1
        } else {
            candidate = event
            candidateCount = 1
        }

        guard candidateCount >= 3 else { return .unchanged }
        emitted = event
        candidate = nil
        candidateCount = 0
        return .changed(event)
    }
}

struct DockPreviewWindow: Equatable, Identifiable, Sendable {
    var id: CGWindowID
    var title: String
    var pid: pid_t
    var frame: CGRect
    var isActivatable: Bool
    var thumbnailData: Data?
}

