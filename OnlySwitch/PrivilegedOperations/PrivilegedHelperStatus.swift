//
//  PrivilegedHelperStatus.swift
//  OnlySwitch
//

import Foundation

/// The UI-safe availability state of the privileged helper.
///
/// Keep diagnostics about ServiceManagement failures out of this value: those
/// belong in private logs, while callers need a stable recovery choice.
enum PrivilegedHelperStatus: Sendable, Equatable {
    case notInstalled
    case requiresApproval
    case enabled
    case disabled
    case unavailable
}

/// A platform-neutral representation used to keep ServiceManagement status
/// mapping deterministic in tests.
enum PrivilegedHelperServiceStatus: Sendable, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

extension PrivilegedHelperStatus {
    init(serviceStatus: PrivilegedHelperServiceStatus) {
        switch serviceStatus {
        case .notRegistered:
            self = .notInstalled
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound, .unknown:
            self = .unavailable
        }
    }
}
