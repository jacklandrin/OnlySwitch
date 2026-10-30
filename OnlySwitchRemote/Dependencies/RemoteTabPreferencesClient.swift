import Dependencies
import Foundation

struct RemoteTabPreferencesClient: Sendable {
    // Save synchronously so rapid changes are persisted in reducer order.
    var save: @Sendable (RemoteTabConfiguration) -> Void = { _ in }
}

extension RemoteTabPreferencesClient: DependencyKey {
    static let liveValue = Self(save: { save($0, defaults: .standard) })
    static let testValue = Self()

    static func preferenceSeed(defaults: UserDefaults = .standard) -> RemoteTabConfiguration {
        .init(
            showsSystemMonitor: defaults.object(forKey: "tabs.showsSystemMonitor") as? Bool ?? true,
            showsSoundMixer: defaults.object(forKey: "tabs.showsSoundMixer") as? Bool ?? true,
            showsBrightness: defaults.object(forKey: "tabs.showsBrightness") as? Bool ?? true,
            showsCodexUsage: defaults.object(forKey: "tabs.showsCodexUsage") as? Bool ?? true,
            showsClaudeUsage: defaults.object(forKey: "tabs.showsClaudeUsage") as? Bool ?? true,
            showsAphrodite: defaults.object(forKey: "tabs.showsAphrodite") as? Bool ?? true
        )
    }

    static func save(_ configuration: RemoteTabConfiguration, defaults: UserDefaults) {
        defaults.set(configuration.showsSystemMonitor, forKey: "tabs.showsSystemMonitor")
        defaults.set(configuration.showsSoundMixer, forKey: "tabs.showsSoundMixer")
        defaults.set(configuration.showsBrightness, forKey: "tabs.showsBrightness")
        defaults.set(configuration.showsCodexUsage, forKey: "tabs.showsCodexUsage")
        defaults.set(configuration.showsClaudeUsage, forKey: "tabs.showsClaudeUsage")
        defaults.set(configuration.showsAphrodite, forKey: "tabs.showsAphrodite")
    }
}

extension DependencyValues {
    var remoteTabPreferences: RemoteTabPreferencesClient {
        get { self[RemoteTabPreferencesClient.self] }
        set { self[RemoteTabPreferencesClient.self] = newValue }
    }
}
