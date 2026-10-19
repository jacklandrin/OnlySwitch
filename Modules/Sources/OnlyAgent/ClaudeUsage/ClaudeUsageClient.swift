import Dependencies
import DependenciesMacros

@DependencyClient
public struct ClaudeUsageClient: Sendable {
    public var fetch: @Sendable (_ allowKeychainPrompt: Bool) async throws -> ClaudeUsageSnapshot
}

extension ClaudeUsageClient: DependencyKey {
    public static let liveValue = Self(fetch: { try await ClaudeUsageService.shared.fetch(allowKeychainPrompt: $0) })
    public static let testValue = Self(fetch: { _ in throw ClaudeUsageError.unsupported })
}

public extension DependencyValues {
    var claudeUsageClient: ClaudeUsageClient {
        get { self[ClaudeUsageClient.self] }
        set { self[ClaudeUsageClient.self] = newValue }
    }
}
