import Defines
import Dependencies
import Extensions
import Foundation

/// Reads and writes whether the desktop pet gets hungry, and tells the running pet about changes.
struct DesktopPetHungerSetting: Sendable {
    var load: @Sendable () -> Bool
    var save: @Sendable (Bool) async -> Void

    static func userDefaults(_ defaults: UserDefaults, notificationCenter: NotificationCenter = .default) -> Self {
        // Both types are documented as thread-safe but are not declared `Sendable`.
        let defaults = UncheckedSendable(defaults)
        let center = UncheckedSendable(notificationCenter)
        let key = UserDefaults.Key.desktopPetHungerEnabled
        return Self(
            load: { defaults.value.object(forKey: key) as? Bool ?? true },
            save: { isEnabled in
                defaults.value.set(isEnabled, forKey: key)
                // Observers such as `AppDelegate` are main-actor isolated, and notifications are
                // delivered on the posting thread, so post from the main actor.
                await MainActor.run {
                    center.value.post(name: .desktopPetNeedsSettingsChanged, object: nil)
                }
            }
        )
    }
}

extension DesktopPetHungerSetting: DependencyKey {
    static let liveValue = Self.userDefaults(.standard)
    static let testValue = Self(
        load: unimplemented("DesktopPetHungerSetting.load", placeholder: true),
        save: unimplemented("DesktopPetHungerSetting.save")
    )
}

extension DependencyValues {
    var desktopPetHungerSetting: DesktopPetHungerSetting {
        get { self[DesktopPetHungerSetting.self] }
        set { self[DesktopPetHungerSetting.self] = newValue }
    }
}
