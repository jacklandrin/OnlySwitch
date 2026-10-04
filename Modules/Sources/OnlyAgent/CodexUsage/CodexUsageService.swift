import Foundation

actor CodexUsageService {
    static let shared = CodexUsageService()

    private let session: URLSession
    private let credentialClient: CodexOAuthCredentialClient
    private let appServerClient: CodexAppServerClient

    init(
        session: URLSession = .shared,
        credentialClient: CodexOAuthCredentialClient = .init(),
        appServerClient: CodexAppServerClient = .init()
    ) {
        self.session = session
        self.credentialClient = credentialClient
        self.appServerClient = appServerClient
    }

    func fetch() async throws -> CodexUsageSnapshot {
        do {
            let token = try await credentialClient.accessToken()
            let oauthSnapshot = try await fetchUsingOAuth(token: token)
            if let cliSnapshot = try? await appServerClient.fetch() {
                return merged(oauth: oauthSnapshot, cli: cliSnapshot)
            }
            return oauthSnapshot
        } catch let error as CodexUsageError where error == .signedOut || error == .unauthorized {
            return try await appServerClient.fetch()
        } catch let error as CodexUsageError {
            throw error
        } catch {
            throw CodexUsageError.network
        }
    }

    private func merged(oauth: CodexUsageSnapshot, cli: CodexUsageSnapshot) -> CodexUsageSnapshot {
        let balance: CodexCreditBalance
        switch cli.creditBalance {
        case .unavailable: balance = oauth.creditBalance
        case .unlimited, .available: balance = cli.creditBalance
        }
        return CodexUsageSnapshot(
            account: .init(email: oauth.account.email ?? cli.account.email, plan: oauth.account.plan ?? cli.account.plan),
            session: oauth.session ?? cli.session,
            weekly: oauth.weekly ?? cli.weekly,
            resetCredits: oauth.resetCredits,
            creditBalance: balance,
            source: oauth.source,
            fetchedAt: oauth.fetchedAt,
            activity: oauth.activity
        )
    }

    private func fetchUsingOAuth(token: String) async throws -> CodexUsageSnapshot {
        let usage = try await response(for: "/backend-api/wham/usage", token: token)
        let creditsData: Data?
        do {
            creditsData = try await response(for: "/backend-api/wham/rate-limit-reset-credits", token: token)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            creditsData = nil
        }

        let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: usage)
        return CodexUsageSnapshot(
            account: .init(email: decoded.email, plan: decoded.plan?.capitalized),
            session: decoded.primaryWindow,
            weekly: decoded.secondaryWindow,
            resetCredits: creditsData.flatMap(CodexResetCreditsResponse.decode) ?? .unavailable,
            creditBalance: creditsData.flatMap(CodexCreditBalanceResponse.decode) ?? .unavailable,
            source: .oauth,
            fetchedAt: .now
        )
    }

    private func response(for path: String, token: String) async throws -> Data {
        guard let url = URL(string: "https://chatgpt.com\(path)") else {
            throw CodexUsageError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw CodexUsageError.network }
        switch http.statusCode {
        case 200 ..< 300: return data
        case 401, 403: throw CodexUsageError.unauthorized
        default: throw CodexUsageError.network
        }
    }
}

private struct CodexUsageResponse: Decodable {
    struct Window: Decodable {
        let usedPercent: Double
        let resetAt: Date?

        enum CodingKeys: String, CodingKey { case usedPercent = "used_percent", resetAt = "reset_at" }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent) ?? 100
            if let seconds = try container.decodeIfPresent(Double.self, forKey: .resetAt) {
                resetAt = Date(timeIntervalSince1970: seconds)
            } else {
                resetAt = nil
            }
        }
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window", secondaryWindow = "secondary_window", planType = "plan_type"
        }
    }

    let rateLimit: RateLimit?
    let email: String?
    let planType: String?

    enum CodingKeys: String, CodingKey { case rateLimit = "rate_limit", email, planType = "plan_type" }

    var primaryWindow: CodexQuotaWindow? { rateLimit?.primaryWindow.map(CodexQuotaWindow.init) }
    var secondaryWindow: CodexQuotaWindow? { rateLimit?.secondaryWindow.map(CodexQuotaWindow.init) }
    var plan: String? { planType ?? rateLimit?.planType }
}

private extension CodexQuotaWindow {
    init(_ window: CodexUsageResponse.Window) {
        self.init(remainingPercent: Self.remainingPercent(fromUsedPercent: window.usedPercent), resetAt: window.resetAt)
    }
}

private enum CodexResetCreditsResponse {
    static func decode(_ data: Data) -> CodexResetCredits? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if root["unlimited"] as? Bool == true { return .unlimited }
        if let count = root["available"] as? Int { return .available(count: count, expiresAt: nil) }
        if let credits = root["credits"] as? [Any] { return .available(count: credits.count, expiresAt: nil) }
        return nil
    }
}

private enum CodexCreditBalanceResponse {
    static func decode(_ data: Data) -> CodexCreditBalance? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if findBool(named: "unlimited", in: root) == true { return .unlimited }
        guard let remaining = findNumber(named: "remaining_balance", in: root)
            ?? findNumber(named: "balance", in: root)
            ?? findNumber(named: "remaining_credits", in: root) else { return nil }
        let limit = findNumber(named: "credit_limit", in: root) ?? findNumber(named: "monthly_limit", in: root)
        let unit = findString(named: "currency", in: root) ?? "credits"
        return .available(remaining: remaining, limit: limit, unit: unit)
    }

    private static func findNumber(named name: String, in object: [String: Any]) -> Double? {
        if let value = object[name] as? Double { return value }
        if let value = object[name] as? Int { return Double(value) }
        for value in object.values where value is [String: Any] {
            if let result = findNumber(named: name, in: value as! [String: Any]) { return result }
        }
        return nil
    }

    private static func findBool(named name: String, in object: [String: Any]) -> Bool? {
        if let value = object[name] as? Bool { return value }
        for value in object.values where value is [String: Any] {
            if let result = findBool(named: name, in: value as! [String: Any]) { return result }
        }
        return nil
    }

    private static func findString(named name: String, in object: [String: Any]) -> String? {
        if let value = object[name] as? String { return value }
        for value in object.values where value is [String: Any] {
            if let result = findString(named: name, in: value as! [String: Any]) { return result }
        }
        return nil
    }
}
