import Foundation
import UIKit

/// Asks iOS for background execution time so a transfer can finish after the app leaves the
/// foreground. Injected into the connection runtime; nothing else calls `UIApplication` for this.
struct RemoteBackgroundTaskClient: Sendable {
    struct Token: Hashable, Sendable {
        let rawValue: Int
    }

    /// Begins a background task, or returns nil when iOS grants none. `expired` runs if iOS ends
    /// the allowance first; the task has then already been ended, and `end` is a no-op for it.
    var begin: @Sendable (_ name: String, _ expired: @escaping @Sendable () -> Void) async -> Token?
    /// Ends a task returned by `begin`. Ending one twice, or after it expired, does nothing.
    var end: @Sendable (Token) async -> Void

    static let noop = Self(begin: { _, _ in nil }, end: { _ in })

    static let live = Self(
        begin: { name, expired in
            await MainActor.run { RemoteBackgroundTaskRegistry.shared.begin(name, expired: expired) }
        },
        end: { token in
            await MainActor.run { RemoteBackgroundTaskRegistry.shared.end(token) }
        }
    )
}

/// Tracks live identifiers so each task is ended exactly once, by the runtime or on expiration.
@MainActor
private final class RemoteBackgroundTaskRegistry {
    static let shared = RemoteBackgroundTaskRegistry()

    private var active: Set<Int> = []

    func begin(_ name: String, expired: @escaping @Sendable () -> Void) -> RemoteBackgroundTaskClient.Token? {
        // The expiration handler can only read the identifier once begin has returned it.
        let identifier = IdentifierBox()
        identifier.value = UIApplication.shared.beginBackgroundTask(withName: name) {
            MainActor.assumeIsolated {
                expired()
                self.end(.init(rawValue: identifier.value.rawValue))
            }
        }
        guard identifier.value != .invalid else { return nil }
        active.insert(identifier.value.rawValue)
        return .init(rawValue: identifier.value.rawValue)
    }

    func end(_ token: RemoteBackgroundTaskClient.Token) {
        guard active.remove(token.rawValue) != nil else { return }
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: token.rawValue))
    }

    @MainActor
    private final class IdentifierBox {
        var value = UIBackgroundTaskIdentifier.invalid
    }
}
