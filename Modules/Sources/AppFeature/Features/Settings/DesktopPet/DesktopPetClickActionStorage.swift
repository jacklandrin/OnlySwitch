import Dependencies
import Extensions
import Foundation

/// Persists the desktop pet click action as JSON in `UserDefaults`; anything unreadable reads as `.onlyControl`.
struct DesktopPetClickActionStorage: Sendable {
    var load: @Sendable () -> DesktopPetClickAction
    var save: @Sendable (DesktopPetClickAction) -> Void

    static func userDefaults(
        _ defaults: UserDefaults,
        key: String = UserDefaults.Key.desktopPetClickAction
    ) -> Self {
        // `UserDefaults` is documented as thread-safe but not declared `Sendable`.
        let defaults = UncheckedSendable(defaults)
        return Self(
            load: {
                guard let data = defaults.value.data(forKey: key),
                      let action = try? JSONDecoder().decode(DesktopPetClickAction.self, from: data)
                else { return .onlyControl }
                return action
            },
            save: { action in
                guard let data = try? JSONEncoder().encode(action) else { return }
                defaults.value.set(data, forKey: key)
            }
        )
    }
}

extension DesktopPetClickActionStorage: DependencyKey {
    static let liveValue = Self.userDefaults(.standard)
    static let testValue = Self(
        load: unimplemented("DesktopPetClickActionStorage.load", placeholder: .onlyControl),
        save: unimplemented("DesktopPetClickActionStorage.save")
    )
}

extension DependencyValues {
    var desktopPetClickActionStorage: DesktopPetClickActionStorage {
        get { self[DesktopPetClickActionStorage.self] }
        set { self[DesktopPetClickActionStorage.self] = newValue }
    }
}
