import AppKit
import Dependencies
import Extensions
import Foundation

struct OnlyRemoteCampaignClient: Sendable {
    var currentVersion: @Sendable () -> String
    var acknowledgedVersion: @Sendable () -> String?
    var markAcknowledged: @Sendable (String) async -> Void
    var openAppStore: @Sendable () async -> Void
    var openRemoteAccessSettings: @Sendable () async -> Void
}

extension OnlyRemoteCampaignClient: DependencyKey {
    static let campaignVersion = "onlyremote-app-store-launch-v1"
    static let appStoreURL = URL(
        string: "https://apps.apple.com/us/app/onlyremote/id6793657946"
    )!

    static var liveValue: Self {
        Self(
            currentVersion: { campaignVersion },
            acknowledgedVersion: {
                UserDefaults.standard.string(
                    forKey: UserDefaults.Key.onlyRemoteCampaignAcknowledgedVersion
                )
            },
            markAcknowledged: { version in
                UserDefaults.standard.set(
                    version,
                    forKey: UserDefaults.Key.onlyRemoteCampaignAcknowledgedVersion
                )
            },
            openAppStore: {
                await MainActor.run {
                    _ = NSWorkspace.shared.open(appStoreURL)
                }
            },
            openRemoteAccessSettings: {
                await MainActor.run {
                    SettingsVM.shared.selection = .iOSRemote
                    SettingsWindow.shared.show()
                }
            }
        )
    }

    static var testValue: Self {
        Self(
            currentVersion: { "test-onlyremote-campaign" },
            acknowledgedVersion: { nil },
            markAcknowledged: { _ in },
            openAppStore: {},
            openRemoteAccessSettings: {}
        )
    }
}

extension DependencyValues {
    var onlyRemoteCampaign: OnlyRemoteCampaignClient {
        get { self[OnlyRemoteCampaignClient.self] }
        set { self[OnlyRemoteCampaignClient.self] = newValue }
    }
}
