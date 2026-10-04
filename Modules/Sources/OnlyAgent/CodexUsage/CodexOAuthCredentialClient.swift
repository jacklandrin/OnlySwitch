import Foundation

actor CodexOAuthCredentialClient {
    private let fileManager: FileManager
    private let environment: [String: String]

    init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func accessToken() async throws -> String {
        let url = authURL()
        for attempt in 0 ..< 3 {
            try Task.checkCancellation()
            if let data = try? Data(contentsOf: url), let token = Self.token(from: data) {
                return token
            }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(50)) }
        }
        throw CodexUsageError.signedOut
    }

    private func authURL() -> URL {
        if let home = environment["CODEX_HOME"], home.isEmpty == false {
            return URL(fileURLWithPath: home).appending(path: "auth.json")
        }
        return fileManager.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
    }

    private static func token(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let token = root["access_token"] as? String, token.isEmpty == false { return token }
        if let tokens = root["tokens"] as? [String: Any], let token = tokens["access_token"] as? String, token.isEmpty == false { return token }
        return nil
    }
}
