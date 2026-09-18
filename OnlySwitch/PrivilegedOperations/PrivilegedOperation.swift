//
//  PrivilegedOperation.swift
//  OnlySwitch
//
//  Shared by the app and the privileged helper target.
//

import Foundation

/// The complete vocabulary of operations the privileged helper is allowed to perform.
///
/// Keep this type closed: adding a case is a security-sensitive change because it adds
/// a new root-level capability to the helper.
enum PrivilegedOperation: String, CaseIterable, Sendable, Codable {
    case lowPowerMode
    case clamshellSleepDisabled

    init(requestName: String) throws {
        guard let operation = Self(rawValue: requestName) else {
            throw PrivilegedOperationError.unsupportedOperation
        }

        self = operation
    }

    /// The fixed arguments accepted by `/usr/bin/pmset` for this operation.
    ///
    /// This deliberately builds arguments from an exhaustive switch instead of
    /// accepting caller-provided command text or argument values.
    func pmsetArguments(enabled: Bool) -> [String] {
        switch self {
        case .lowPowerMode:
            ["-a", "lowpowermode", enabled ? "1" : "0"]
        case .clamshellSleepDisabled:
            ["-a", "disablesleep", enabled ? "1" : "0"]
        }
    }
}

/// A typed request decoded from the XPC wire values before it reaches the executor.
struct PrivilegedOperationRequest: Sendable, Codable, Equatable {
    let operation: PrivilegedOperation
    let enabled: Bool

    init(operation: PrivilegedOperation, enabled: Bool) {
        self.operation = operation
        self.enabled = enabled
    }

    init(requestName: String, enabled: Bool) throws {
        try self.init(operation: PrivilegedOperation(requestName: requestName), enabled: enabled)
    }
}

/// Errors deliberately exposed across the helper boundary.
enum PrivilegedOperationError: Int, Error, Sendable, Equatable {
    case unsupportedOperation = 1

    var nsError: NSError {
        NSError(domain: Self.domain, code: rawValue)
    }

    private static let domain = "com.jacklandrin.OnlySwitch.PrivilegedOperation"
}

/// The Objective-C-compatible XPC surface shared by the app and root helper.
@objc protocol PrivilegedOperationXPC {
    func setOperation(_ name: String, enabled: Bool, reply: @escaping (NSError?) -> Void)
}
