import Foundation
#if os(macOS)
import LocalAuthentication
import Security
#endif

/// A short-lived credential value. It is deliberately neither Codable nor printable.
struct ClaudeOAuthCredential: Sendable {
    let accessToken: String
    let expiresAt: Date?
    let account: ClaudeUsageAccount

    static func decode(_ data: Data, now: Date) throws -> Self {
        guard data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClaudeUsageError.signedOut }
        if let scopes = oauth["scopes"] as? [String], !scopes.contains("user:profile") { throw ClaudeUsageError.unauthorized }
        let expiry = ClaudeUsageResponse.number(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        if let expiry, expiry <= now { throw ClaudeUsageError.unauthorized }
        let account = root["account"] as? [String: Any] ?? [:]
        return .init(accessToken: token, expiresAt: expiry, account: .init(
            email: account["email"] as? String ?? account["email_address"] as? String ?? account["emailAddress"] as? String,
            plan: oauth["subscriptionType"] as? String ?? oauth["rateLimitTier"] as? String))
    }
}

struct ClaudeOAuthCredentialClient: Sendable {
    var read: @Sendable (_ allowKeychainPrompt: Bool) async throws -> ClaudeOAuthCredential

    static let live = Self(read: { allowPrompt in
        #if os(macOS)
        return try await ClaudeOAuthCredentialReader.live.read(allowKeychainPrompt: allowPrompt)
        #else
        throw ClaudeUsageError.unsupported
        #endif
    })
}

struct ClaudeOAuthCredentialReader: Sendable {
    let configDirectory: String?
    let homeDirectory: URL
    let readFile: @Sendable (URL) throws -> Data
    let readKeychain: @Sendable (String, Bool) throws -> Data?
    var now: @Sendable () -> Date = { Date() }

    func read(allowKeychainPrompt: Bool) async throws -> ClaudeOAuthCredential {
        try Task.checkCancellation()
        let configured = configDirectory.flatMap { $0.isEmpty ? nil : $0 }
        guard configured?.hasPrefix("/") != false else { throw ClaudeUsageError.unsupported }
        let directory = configured.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
        var lastFailure = ClaudeUsageError.signedOut
        do { return try ClaudeOAuthCredential.decode(readFile(directory.appending(path: ".credentials.json")), now: now()) }
        catch is CancellationError { throw CancellationError() }
        catch let error as ClaudeUsageError {
            // A known but expired/insufficiently scoped file is this profile's account.
            // Falling through could silently display a different account from Keychain.
            guard error == .signedOut else { throw error }
            lastFailure = error
        }
        catch {}
        // A custom profile must never silently use another profile's default Keychain account.
        if configured != nil && directory.standardizedFileURL != homeDirectory.appending(path: ".claude", directoryHint: .isDirectory).standardizedFileURL { throw lastFailure }
        try Task.checkCancellation()
        do {
            if let data = try readKeychain("Claude Code-credentials", allowKeychainPrompt) {
                return try ClaudeOAuthCredential.decode(data, now: now())
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as ClaudeUsageError { throw error }
        catch { throw ClaudeUsageError.permissionDenied }
        throw lastFailure
    }

    #if os(macOS)
    static let live = Self(
        configDirectory: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
        readFile: { url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw ClaudeUsageError.signedOut }
            return try Data(contentsOf: url)
        },
        readKeychain: { service, allowPrompt in
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if !allowPrompt {
                let context = LAContext()
                context.interactionNotAllowed = true
                query[kSecUseAuthenticationContext as String] = context
            }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess: return result as? Data
            case errSecItemNotFound: return nil
            case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed: throw ClaudeUsageError.permissionDenied
            default: throw ClaudeUsageError.signedOut
            }
        })
    #endif
}
