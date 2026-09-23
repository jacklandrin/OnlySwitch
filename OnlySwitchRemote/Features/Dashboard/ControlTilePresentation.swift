import Foundation
import RemoteCore

struct ControlTilePresentation: Equatable, Sendable {
    enum VisualState: Equatable, Sendable {
        case on
        case off
        case ready
        case pending
        case stale
        case offline
        case unavailable
        case failed
    }

    let visualState: VisualState
    let lastKnownIsOn: Bool?
    let secondaryInformation: String?
    let unavailableReason: String?

    init(
        descriptor: RemoteControlDescriptor,
        status: DashboardFeature.TileStatus?,
        connectionState: DashboardFeature.ConnectionState,
        isRequestInFlight: Bool,
        actionFailure: String?
    ) {
        lastKnownIsOn = status?.value.isOn
        secondaryInformation = status?.value.secondaryInformation

        if descriptor.isAvailable == false {
            unavailableReason = descriptor.localizedUnavailableReason
                ?? String(localized: "Unavailable on this Mac")
        } else if status?.value.isAvailable == false {
            unavailableReason = status?.value.unavailableReason
                .map(descriptor.localizedUnavailableReason)
                ?? String(localized: "Unavailable on this Mac")
        } else {
            unavailableReason = nil
        }

        let isOffline: Bool
        switch connectionState {
        case .offline, .revoked:
            isOffline = true
        case .idle, .connecting, .authenticated:
            isOffline = false
        }

        if unavailableReason != nil {
            visualState = .unavailable
        } else if isRequestInFlight || status?.value.isProcessing == true {
            visualState = .pending
        } else if isOffline {
            visualState = .offline
        } else if status?.isStale == true || connectionState == .connecting {
            visualState = .stale
        } else if actionFailure != nil {
            visualState = .failed
        } else {
            switch descriptor.behavior {
            case .button:
                visualState = .ready
            case .switch, .player:
                visualState = lastKnownIsOn == true ? .on : .off
            }
        }
    }

    var accessibilityValue: String {
        switch visualState {
        case .on:
            String(localized: "On")
        case .off:
            String(localized: "Off")
        case .ready:
            String(localized: "Ready")
        case .pending:
            String(localized: "Working")
        case .stale:
            String(localized: "Offline, showing last known status")
        case .offline:
            String(localized: "Offline")
        case .unavailable:
            if let unavailableReason {
                String(localized: "Unavailable: \(unavailableReason)")
            } else {
                String(localized: "Unavailable on this Mac")
            }
        case .failed:
            String(localized: "Action Failed")
        }
    }

    var displaysActivityIndicator: Bool {
        visualState == .pending
    }
}
