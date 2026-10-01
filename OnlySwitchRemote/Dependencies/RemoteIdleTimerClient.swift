import Dependencies
import DependenciesMacros
import Foundation
import UIKit

@DependencyClient
struct RemoteIdleTimerClient: Sendable {
    var savePreference: @Sendable (Bool) async -> Void = { _ in }
    var setIdleTimerDisabled: @Sendable (Bool) async -> Void = { _ in }
}

extension RemoteIdleTimerClient: DependencyKey {
    static let liveValue = Self(
        savePreference: { value in
            await MainActor.run {
                UserDefaults.standard.set(value, forKey: preferenceKey)
            }
        },
        setIdleTimerDisabled: { value in
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = value
            }
        }
    )

    static let testValue = Self()

    private static let preferenceKey = "keepScreenAwake"

    static func preferenceSeed(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: preferenceKey)
    }
}

extension DependencyValues {
    var remoteIdleTimer: RemoteIdleTimerClient {
        get { self[RemoteIdleTimerClient.self] }
        set { self[RemoteIdleTimerClient.self] = newValue }
    }
}
