//
//  PrivilegedAccessPresentation.swift
//  OnlySwitch
//

import Foundation

/// Stable localization keys for the privileged-access recovery surface.
/// Keeping these values separate from the view makes recovery behavior
/// deterministic and directly testable without rendering SwiftUI.
struct PrivilegedAccessPresentation: Equatable, Sendable {
    let titleKey: String
    let detailKey: String
    let primaryAction: PrivilegedAccessAction?

    init(status: PrivilegedHelperStatus) {
        switch status {
        case .enabled:
            self = .init(
                titleKey: "Privileged access enabled",
                detailKey: "OnlySwitch can change supported switches without asking for your password again.",
                primaryAction: nil
            )
        case .notInstalled:
            self = .init(
                titleKey: "One-time authorization required",
                detailKey: "Authorize OnlySwitch once to use supported switches without repeated password prompts.",
                primaryAction: .install
            )
        case .requiresApproval:
            self = .init(
                titleKey: "Authorization approval needed",
                detailKey: "Approve OnlySwitch's privileged helper in System Settings to continue.",
                primaryAction: .openSystemSettings
            )
        case .disabled:
            self = .init(
                titleKey: "Privileged access disabled",
                detailKey: "The privileged helper is disabled. Repair it or enable it in System Settings.",
                primaryAction: .repair
            )
        case .unavailable:
            self = .init(
                titleKey: "Privileged helper unavailable",
                detailKey: "OnlySwitch could not find its privileged helper. Repair privileged access to continue.",
                primaryAction: .repair
            )
        }
    }
}

enum PrivilegedAccessAction: Sendable, Equatable {
    case install
    case repair
    case openSystemSettings
}
