#if os(macOS)
import Foundation

public enum TailscaleCLI {
    public static func decodeAccounts(_ data: Data) throws -> [TailscaleAccount] {
        struct Profile: Decodable { var id: String; var nickname: String?; var tailnet: String; var account: String; var selected: Bool }
        do {
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
            guard Set(profiles.map(\.id)).count == profiles.count,
                  profiles.filter(\.selected).count <= 1,
                  profiles.allSatisfy({ !$0.id.isEmpty && !$0.id.hasPrefix("-") }) else { throw TailscaleError.invalidResponse }
            return profiles.map { .init(id: $0.id, nickname: $0.nickname ?? "", tailnet: $0.tailnet, email: $0.account, isActive: $0.selected) }
        } catch { throw TailscaleError.invalidResponse }
    }

    public static func decodeStatus(_ data: Data) throws -> TailscaleConnection {
        struct Status: Decodable {
            struct Node: Decodable { var UserID: Int64?; var KeyExpiry: String?; var Expired: Bool?; var TailscaleIPs: [String]? }
            struct User: Decodable { var DisplayName: String?; var LoginName: String? }
            struct Tailnet: Decodable { var Name: String? }
            struct Exit: Decodable { var ID: String? }
            var BackendState: String
            var `Self`: Node?
            var User: [String: User]?
            var CurrentTailnet: Tailnet?
            var ExitNodeStatus: Exit?
            var TailscaleIPs: [String]?
        }
        do {
            let value = try JSONDecoder().decode(Status.self, from: data)
            var status: TailscaleConnection.Status = switch value.BackendState {
            case "Running": .running
            case "Stopped": .stopped
            case "NeedsLogin", "NoState": .needsLogin
            case "NeedsMachineAuth": .needsMachineAuth
            case "Starting": .starting
            default: .unavailable
            }
            if value.Self?.Expired == true { status = .needsLogin }
            let user = value.Self?.UserID.flatMap { value.User?[String($0)] }
            let expiry = value.Self?.KeyExpiry.flatMap { string in
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: string) { return date }
                formatter.formatOptions.insert(.withFractionalSeconds)
                return formatter.date(from: string)
            }
            let address = primaryIPAddress(in: value.TailscaleIPs) ?? primaryIPAddress(in: value.Self?.TailscaleIPs)
            return .init(status: status, displayName: user?.DisplayName, email: user?.LoginName, tailnet: value.CurrentTailnet?.Name, expiry: expiry, hasExitNode: value.ExitNodeStatus?.ID != nil, primaryIPAddress: address)
        } catch { throw TailscaleError.invalidResponse }
    }

    private static func primaryIPAddress(in addresses: [String]?) -> String? {
        let valid = (addresses ?? []).compactMap { TailscaleConnection.validatedIPAddress($0) }
        // Every valid literal without a colon is native IPv4. A dotted IPv4
        // suffix inside an IPv6 literal must remain in the IPv6 preference tier.
        return valid.first(where: { !$0.contains(":") }) ?? valid.first
    }

    public static func decodePreferences(_ data: Data) throws -> [TailscalePreference: Bool] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TailscaleError.invalidResponse }
        var values: [TailscalePreference: Bool] = [:]
        // JSON booleans must not be inferred from missing fields or integer values.
        for preference in TailscalePreference.allCases {
            guard let number = object[flag(for: preference)] as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { continue }
            values[preference] = preference == .allowIncoming ? !number.boolValue : number.boolValue
        }
        return values
    }

    public static func arguments(for operation: TailscaleOperation) throws -> [String] {
        switch operation {
        case .connect: return ["up"]
        case .disconnect: return ["down"]
        case .login: return ["login"]
        case .renew: return ["up", "--force-reauth"]
        case .logout: return ["logout"]
        case .switchAccount(let id):
            try validateAccount(id)
            return ["switch", id]
        case .setPreference(let preference, let value):
            let flagValue = preference == .allowIncoming ? !value : value
            return ["set", "--\(flag(for: preference))=\(flagValue)"]
        case .forAccount(let id, _):
            try validateAccount(id)
            return try arguments(for: operation.baseOperation)
        }
    }

    public static func authorizationURL(in output: String) -> URL? {
        // CLI login writes a complete HTTPS link on its own line to stderr.
        for token in output.split(whereSeparator: { $0.isWhitespace || $0 == "\"" }) {
            guard let components = URLComponents(string: String(token)), components.scheme == "https",
                  components.host == "login.tailscale.com", components.user == nil, components.password == nil,
                  components.port == nil, components.query == nil, components.fragment == nil,
                  components.path.hasPrefix("/a/"), components.path.count > 3,
                  let url = components.url else { continue }
            return url
        }
        return nil
    }

    static func validateAccount(_ id: String) throws {
        guard !id.isEmpty, !id.hasPrefix("-"), id.utf8.count <= 1024,
              !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw TailscaleError.invalidAccount }
    }
    private static func flag(for preference: TailscalePreference) -> String {
        switch preference {
        case .allowIncoming: "shields-up"
        case .acceptDNS: "accept-dns"
        case .acceptRoutes: "accept-routes"
        case .advertiseExitNode: "advertise-exit-node"
        case .allowLANAccess: "exit-node-allow-lan-access"
        }
    }
}
#endif
