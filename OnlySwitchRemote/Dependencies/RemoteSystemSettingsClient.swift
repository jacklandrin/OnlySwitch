import Dependencies
import DependenciesMacros
import Foundation
import UIKit

@DependencyClient
struct RemoteSystemSettingsClient: Sendable {
    var openAppSettings: @Sendable () async -> Void
}

extension RemoteSystemSettingsClient: DependencyKey {
    static let liveValue = Self(
        openAppSettings: {
            await MainActor.run {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    )

    static let testValue = Self(openAppSettings: {})
}

extension DependencyValues {
    var remoteSystemSettings: RemoteSystemSettingsClient {
        get { self[RemoteSystemSettingsClient.self] }
        set { self[RemoteSystemSettingsClient.self] = newValue }
    }
}
