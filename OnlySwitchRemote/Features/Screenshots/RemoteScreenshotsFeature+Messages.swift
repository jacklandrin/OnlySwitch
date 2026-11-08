import Foundation
import RemoteCore

// MARK: - User-facing copy

extension RemoteScreenshotsFeature {
    /// Protocol `message`s are English diagnostics; the user sees localized copy keyed by error code.
    static func availabilityMessage(for error: RemoteProtocolError) -> String {
        switch error.code {
        case .upgradeRequired, .actionNotSupported:
            String(localized: "This Mac needs a newer OnlySwitch version to use Screenshots.")
        case .requestTimedOut:
            String(localized: "The Mac did not respond in time. Try again.")
        default:
            String(localized: "The Mac could not share its screenshots.")
        }
    }

    static func downloadErrorMessage(for error: RemoteProtocolError, isRecording: Bool = false) -> String {
        switch error.code {
        case .controlNotFound:
            String(localized: "This screenshot is no longer on the Mac.")
        case .controlUnavailable where isRecording:
            String(localized: "This item changed on the Mac or is too large to transfer.")
        case .controlUnavailable:
            String(localized: "This screenshot changed on the Mac or is too large to transfer.")
        case .requestTimedOut:
            String(localized: "The Mac did not respond in time. Try again.")
        case .invalidFrame:
            String(localized: "The screenshot transfer was interrupted. Try again.")
        case .authenticationFailed:
            String(localized: "Connect to the Mac to download this screenshot.")
        default:
            String(localized: "The screenshot could not be downloaded.")
        }
    }

    static func deleteErrorMessage(for error: RemoteProtocolError) -> String {
        switch error.code {
        case .controlNotFound:
            String(localized: "This screenshot is no longer on the Mac.")
        case .requestTimedOut:
            String(localized: "The Mac did not respond in time. Try again.")
        case .authenticationFailed:
            String(localized: "Connect to the Mac to delete this screenshot.")
        default:
            String(localized: "The Mac could not move the screenshot to the Trash.")
        }
    }

    /// Non-protocol failures (for example a cache write) get the generic copy for their operation.
    static func unexpected(_ error: any Error) -> RemoteProtocolError {
        RemoteProtocolError(code: .executionFailed, message: String(describing: error))
    }
}
