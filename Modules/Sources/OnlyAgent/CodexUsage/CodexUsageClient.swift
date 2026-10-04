import Dependencies
import DependenciesMacros

@DependencyClient
public struct CodexUsageClient: Sendable {
    public var fetch: @Sendable () async throws -> CodexUsageSnapshot
}

extension CodexUsageClient: DependencyKey {
    public static let liveValue = Self(fetch: {
        try await CodexUsageService.shared.fetch()
    })

    public static let testValue = Self(fetch: {
        throw CodexUsageError.unsupported
    })
}

public extension DependencyValues {
    var codexUsageClient: CodexUsageClient {
        get { self[CodexUsageClient.self] }
        set { self[CodexUsageClient.self] = newValue }
    }
}
