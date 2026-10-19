import Foundation

actor ClaudeUsageService {
    static let shared = ClaudeUsageService(credentialClient: .live, transport: ClaudeOAuthTransport.fetch, now: { Date() },
                                           renewSession: { await ClaudeCodeSessionRenewal.shared.renewIfAllowed() })
    private let credentialClient: ClaudeOAuthCredentialClient
    private let transport: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let now: @Sendable () -> Date
    private let renewSession: @Sendable () async -> Bool

    init(credentialClient: ClaudeOAuthCredentialClient, transport: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse), now: @escaping @Sendable () -> Date,
         renewSession: @escaping @Sendable () async -> Bool = { false }) {
        self.credentialClient = credentialClient; self.transport = transport; self.now = now; self.renewSession = renewSession
    }

    func fetch(allowKeychainPrompt: Bool = false) async throws -> ClaudeUsageSnapshot {
        do {
            return try await fetchOnce(allowKeychainPrompt: allowKeychainPrompt)
        } catch let error as ClaudeUsageError where error == .unauthorized {
            // Claude Code only renews its access token while it runs. Ask it to renew its own session,
            // then read the credential it stored once more; OnlySwitch never rotates the refresh token itself.
            guard await renewSession() else { throw error }
            try Task.checkCancellation()
            return try await fetchOnce(allowKeychainPrompt: allowKeychainPrompt)
        }
    }

    private func fetchOnce(allowKeychainPrompt: Bool) async throws -> ClaudeUsageSnapshot {
        do {
            try Task.checkCancellation()
            let credential = try await credentialClient.read(allowKeychainPrompt)
            if let expiry = credential.expiresAt, expiry <= now() { throw ClaudeUsageError.unauthorized }
            let data = try await request(path: "usage", token: credential.accessToken)
            var account = credential.account
            if account.email == nil || account.plan == nil {
                do {
                    let profile = try await request(path: "profile", token: credential.accessToken)
                    if let root = try? JSONSerialization.jsonObject(with: profile) as? [String: Any] {
                        let identity = root["account"] as? [String: Any] ?? root
                        let organization = root["organization"] as? [String: Any] ?? [:]
                        account = .init(email: account.email ?? identity["email"] as? String ?? identity["email_address"] as? String ?? identity["emailAddress"] as? String,
                                        plan: account.plan ?? organization["organization_type"] as? String ?? root["subscription_type"] as? String)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch let error as URLError where error.code == .cancelled { throw CancellationError() }
                catch { /* Profile metadata is optional and never replaces a successful usage response. */ }
            }
            try Task.checkCancellation()
            return try ClaudeUsageResponse.decode(data, account: account, fetchedAt: now())
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as ClaudeUsageError { throw error }
        catch { throw ClaudeUsageError.network }
    }

    private func request(path: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/" + path)!)
        request.timeoutInterval = 10
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard response.url?.scheme == "https", response.url?.host == "api.anthropic.com", response.url?.port == nil || response.url?.port == 443 else { throw ClaudeUsageError.invalidResponse }
        switch response.statusCode {
        case 200 ... 299: break
        case 401, 403: throw ClaudeUsageError.unauthorized
        case 429: throw ClaudeUsageError.rateLimited
        default: throw ClaudeUsageError.network
        }
        guard data.count <= 1_048_576 else { throw ClaudeUsageError.invalidResponse }
        return data
    }
}

private final class ClaudeOAuthTransport: NSObject, URLSessionTaskDelegate {
    private static let delegate = ClaudeOAuthTransport()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    static func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClaudeUsageError.invalidResponse }
        guard response.expectedContentLength <= 1_048_576 else { throw ClaudeUsageError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw ClaudeUsageError.invalidResponse }
            data.append(byte)
        }
        return (data, response)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // No redirect is necessary for these fixed OAuth endpoints; never forward a bearer token.
        completionHandler(nil)
    }
}
