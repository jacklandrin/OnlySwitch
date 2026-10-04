import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct CodexLocalUsageClient: Sendable {
    public var scan: @Sendable () async throws -> CodexActivityEstimate
}

extension CodexLocalUsageClient: DependencyKey {
    public static let liveValue = Self(scan: {
        try await CodexLocalUsageScanner().scan()
    })

    public static let testValue = Self(scan: {
        CodexActivityEstimate(dailyUsage: [], isPartial: false)
    })
}

public extension DependencyValues {
    var codexLocalUsageClient: CodexLocalUsageClient {
        get { self[CodexLocalUsageClient.self] }
        set { self[CodexLocalUsageClient.self] = newValue }
    }
}
