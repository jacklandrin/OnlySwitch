#if os(macOS)
import Darwin
import Foundation

public struct TailscaleAccount: Equatable, Identifiable, Sendable {
    public let id: String
    public let nickname: String
    public let tailnet: String
    public let email: String
    public let isActive: Bool
    public init(id: String, nickname: String, tailnet: String, email: String, isActive: Bool) {
        self.id = id; self.nickname = nickname; self.tailnet = tailnet; self.email = email; self.isActive = isActive
    }
    public var title: String { nickname.isEmpty ? email : nickname }
}

public enum TailscalePreference: String, CaseIterable, Sendable {
    case allowIncoming, acceptDNS, acceptRoutes, advertiseExitNode, allowLANAccess
    public var localizationKey: String {
        switch self {
        case .allowIncoming: "Tailscale Allow Incoming"
        case .acceptDNS: "Tailscale Use DNS"
        case .acceptRoutes: "Tailscale Use Subnets"
        case .advertiseExitNode: "Tailscale Run Exit Node"
        case .allowLANAccess: "Tailscale Allow LAN"
        }
    }
}

public struct TailscaleConnection: Equatable, Sendable {
    public enum Status: String, Sendable {
        case running, stopped, needsLogin, needsMachineAuth, starting, unavailable
        public var localizationKey: String {
            switch self {
            case .running: "Tailscale Connected"
            case .stopped: "Tailscale Disconnected"
            case .needsLogin: "Tailscale Login Required"
            case .needsMachineAuth: "Tailscale Approval Required"
            case .starting: "Tailscale Connecting"
            case .unavailable: "Tailscale Unavailable"
            }
        }
    }
    public var status: Status
    public var displayName: String?
    public var email: String?
    public var tailnet: String?
    public var expiry: Date?
    public var hasExitNode: Bool
    public var primaryIPAddress: String?
    public init(status: Status, displayName: String? = nil, email: String? = nil, tailnet: String? = nil, expiry: Date? = nil, hasExitNode: Bool = false, primaryIPAddress: String? = nil) {
        self.status = status; self.displayName = displayName; self.email = email; self.tailnet = tailnet; self.expiry = expiry; self.hasExitNode = hasExitNode; self.primaryIPAddress = primaryIPAddress
    }
    public var requiresAuthentication: Bool { status == .needsLogin || status == .needsMachineAuth }

    /// Accept only complete native IP literals. Callers may validate injected or
    /// hand-built snapshots through the same boundary before offering a copy.
    public static func validatedIPAddress(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count < INET6_ADDRSTRLEN,
              value.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) || byte == 46 || byte == 58
              }) else { return nil }
        // Darwin accepts some zero-padded IPv4 components. Exclude those
        // ambiguous forms, including a dotted IPv4 suffix inside IPv6.
        if value.contains(".") {
            let dotted = value.split(separator: ":", omittingEmptySubsequences: false).last ?? ""
            let octets = dotted.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4, octets.allSatisfy({ !$0.isEmpty && ($0.count == 1 || $0.first != "0") }) else { return nil }
        }
        var ipv4 = in_addr(), ipv6 = in6_addr()
        let valid = value.withCString {
            inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1
        }
        return valid ? value : nil
    }
}

public struct TailscaleSnapshot: Equatable, Sendable {
    public var accounts: [TailscaleAccount]
    public var connection: TailscaleConnection
    public var preferences: [TailscalePreference: Bool]
    public var preferencesAvailable: Bool
    public init(accounts: [TailscaleAccount], connection: TailscaleConnection, preferences: [TailscalePreference: Bool] = [:], preferencesAvailable: Bool = false) {
        self.accounts = accounts; self.connection = connection; self.preferences = preferences; self.preferencesAvailable = preferencesAvailable
    }
}

public enum TailscaleOperation: Equatable, Sendable {
    case connect, disconnect, login, renew, logout
    case switchAccount(String)
    case setPreference(TailscalePreference, Bool)
    case forAccount(String, TailscaleAccountOperation)
    public var isAuthorization: Bool { baseOperation == .login || baseOperation == .renew }
    var expectedAccountID: String? {
        if case .forAccount(let id, _) = self { return id }
        return nil
    }
    var baseOperation: Self {
        guard case .forAccount(_, let intent) = self else { return self }
        return switch intent {
        case .connect: .connect
        case .disconnect: .disconnect
        case .logout: .logout
        case .renew: .renew
        case .setPreference(let preference, let enabled): .setPreference(preference, enabled)
        }
    }
}

/// A Settings intent is bound to the account the user actually reviewed. This
/// cannot silently follow an account switched in the official application.
public enum TailscaleAccountOperation: Equatable, Sendable {
    case connect, disconnect, logout, renew
    case setPreference(TailscalePreference, Bool)
}

public enum TailscaleError: Error, Equatable, Sendable {
    case notInstalled, unavailable, authenticationRequired, invalidResponse
    case unsupported, invalidAccount, busy, timedOut, outputLimit, commandFailed
    public var localizationKey: String {
        switch self {
        case .notInstalled: "Tailscale Install Required"
        case .unavailable: "Tailscale Client Unavailable"
        case .authenticationRequired: "Tailscale Login Required"
        case .invalidResponse: "Tailscale Invalid Response"
        case .unsupported: "Tailscale Unsupported"
        case .invalidAccount: "Tailscale Invalid Account"
        case .busy: "Tailscale Busy"
        case .timedOut: "Tailscale Timed Out"
        case .outputLimit: "Tailscale Output Limit"
        case .commandFailed: "Tailscale Operation Failed"
        }
    }
    public static func sanitized(_ error: any Error) -> Self { (error as? Self) ?? .commandFailed }
}

/// The main app's string catalog supplies these translations to the package view.
public enum TailscaleStrings {
    public static let keys = [
        "Tailscale", "Tailscale Accounts", "Tailscale Settings", "Tailscale Add Account", "Tailscale Switch Account",
        "Tailscale Log Out", "Tailscale Renew", "Tailscale Refresh", "Tailscale Open App", "Tailscale Install",
        "Tailscale Cancel", "Tailscale Active Account", "Tailscale No Accounts", "Tailscale Account Notice",
        "Tailscale Tailnet", "Tailscale Email", "Tailscale Status", "Tailscale Expiry", "Tailscale Connection",
        "Tailscale Allow Incoming", "Tailscale Use DNS", "Tailscale Use Subnets", "Tailscale Run Exit Node", "Tailscale Allow LAN",
        "Tailscale Network Settings", "Tailscale Subnets Notice", "Tailscale Exit Node Notice", "Tailscale LAN Notice",
        "Tailscale Preferences Unavailable", "Tailscale App Settings Notice", "Tailscale Login Waiting",
        "Tailscale Logout Confirmation", "Tailscale Connected", "Tailscale Disconnected", "Tailscale Login Required",
        "Tailscale Approval Required", "Tailscale Connecting", "Tailscale Unavailable", "Tailscale Install Required",
        "Tailscale Client Unavailable", "Tailscale Invalid Response", "Tailscale Unsupported", "Tailscale Invalid Account",
        "Tailscale Busy", "Tailscale Timed Out", "Tailscale Output Limit", "Tailscale Operation Failed"
    ]
}
#endif
