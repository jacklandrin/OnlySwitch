import AppKit
import ComposableArchitecture
import Foundation
import SystemConfiguration

struct RemoteAccessPreferences: Equatable, Sendable {
    var isEnabled: Bool
    var displayName: String
}

struct RemoteAccessPreferencesClient: Sendable {
    var load: @Sendable () -> RemoteAccessPreferences
    var setEnabled: @Sendable (Bool) async -> Void
    var setDisplayName: @Sendable (String) async -> Void
}

extension RemoteAccessPreferencesClient: DependencyKey {
    static let enabledKey = "remoteAccess.isEnabled"
    static let displayNameKey = "remoteAccess.displayName"

    static var liveValue: Self {
        Self(
            load: {
                let defaults = UserDefaults.standard
                return RemoteAccessPreferences(
                    isEnabled: defaults.bool(forKey: enabledKey),
                    displayName: defaults.string(forKey: displayNameKey) ?? defaultDisplayName
                )
            },
            setEnabled: { UserDefaults.standard.set($0, forKey: enabledKey) },
            setDisplayName: { UserDefaults.standard.set($0, forKey: displayNameKey) }
        )
    }

    static var testValue: Self {
        Self(
            load: { .init(isEnabled: false, displayName: defaultDisplayName) },
            setEnabled: { _ in },
            setDisplayName: { _ in }
        )
    }

    static var defaultDisplayName: String {
        resolvedDefaultDisplayName(
            computerName: SCDynamicStoreCopyComputerName(nil, nil) as String?,
            hostName: ProcessInfo.processInfo.hostName
        )
    }

    static func resolvedDefaultDisplayName(
        computerName: String?,
        hostName: String
    ) -> String {
        let computerName = computerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let computerName, computerName.isEmpty == false { return computerName }
        let hostName = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return hostName.isEmpty ? "OnlySwitch Mac".localized() : hostName
    }
}

extension DependencyValues {
    var remoteAccessPreferences: RemoteAccessPreferencesClient {
        get { self[RemoteAccessPreferencesClient.self] }
        set { self[RemoteAccessPreferencesClient.self] = newValue }
    }
}

struct RemotePasteboardClient: Sendable {
    var copy: @Sendable (String) async -> Bool
}

extension RemotePasteboardClient: DependencyKey {
    static var liveValue: Self {
        Self { value in
            await MainActor.run {
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(value, forType: .string)
            }
        }
    }

    static var testValue: Self { Self { _ in false } }
}

extension DependencyValues {
    var remotePasteboard: RemotePasteboardClient {
        get { self[RemotePasteboardClient.self] }
        set { self[RemotePasteboardClient.self] = newValue }
    }
}
