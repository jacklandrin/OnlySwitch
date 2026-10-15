import ComposableArchitecture
import Foundation

@DependencyClient
public struct AphroditeWebStorageClient: Sendable {
    public var removeData: @Sendable (AphroditeAppOrigin) async -> Void
}

extension AphroditeWebStorageClient: DependencyKey {
    public static let liveValue = Self(
        removeData: { origin in
            #if os(macOS)
            await removeWebKitData(for: origin)
            #endif
        }
    )

    public static let testValue = Self(removeData: { _ in })
}

public extension DependencyValues {
    var aphroditeWebStorage: AphroditeWebStorageClient {
        get { self[AphroditeWebStorageClient.self] }
        set { self[AphroditeWebStorageClient.self] = newValue }
    }
}

#if os(macOS)
@MainActor
private func removeWebKitData(for origin: AphroditeAppOrigin) async {
    guard #available(macOS 26.0, *) else { return }
    let operation = AphroditeStorageCleanupOperation(origin: origin)
    await operation.run()
}
#endif
