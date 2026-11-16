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
    /// False while the Dock item's frame may still be animating; windows can
    /// load, but the preview must not be positioned from this frame yet.
    var isSettled = true
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

// A new app is emitted after `identifyCount` direct hits, marked unsettled, so
// window loading overlaps the Dock reveal or magnification without loading
// every app the pointer merely crosses. Its frame is emitted as settled only
// after `settleCount` equal direct hits (~160 ms at the observer's 40 ms poll);
// later geometry changes for the same app also wait until stable so a visible
// preview never jumps.
struct DockHoverStabilizer: Sendable {
    enum Update: Equatable {
        case unchanged
        case changed(DockHoverEvent?)
    }

    static let identifyCount = 2
    static let settleCount = 5

    private var candidate: DockHoverEvent?
    private var candidateCount = 0
    private var pidCandidate: pid_t?
    private var pidCount = 0
    private var emitted: DockHoverEvent?

    mutating func update(
        _ event: DockHoverEvent?,
        isDirectHit: Bool = true
    ) -> Update {
        guard var event else {
            candidate = nil
            candidateCount = 0
            pidCandidate = nil
            pidCount = 0
            guard emitted != nil else { return .unchanged }
            emitted = nil
            return .changed(nil)
        }

        guard isDirectHit else {
            candidate = nil
            candidateCount = 0
            pidCandidate = nil
            pidCount = 0
            return .unchanged
        }

        event.isSettled = true
        if candidate == event {
            candidateCount += 1
        } else {
            candidate = event
            candidateCount = 1
        }

        if pidCandidate == event.pid {
            pidCount += 1
        } else {
            pidCandidate = event.pid
            pidCount = 1
        }

        guard emitted?.pid == event.pid else {
            guard pidCount >= Self.identifyCount else { return .unchanged }
            var unsettled = event
            unsettled.isSettled = false
            emitted = unsettled
            return .changed(unsettled)
        }

        guard candidateCount >= Self.settleCount, event != emitted else { return .unchanged }
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

