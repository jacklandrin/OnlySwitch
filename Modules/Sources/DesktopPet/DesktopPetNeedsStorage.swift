import Dependencies
import Foundation

/// Persists the pet's needs as JSON and reads the user's hunger setting. Unreadable data reads as
/// "never fed" (the reducer then starts a fresh meal), and a missing setting reads as enabled.
public struct DesktopPetNeedsStorage: Sendable {
    public static let needsKey = "desktopPetNeedsKey"
    public static let hungerEnabledKey = "desktopPetHungerEnabledKey"

    public var loadNeeds: @Sendable () -> DesktopPetNeeds?
    public var saveNeeds: @Sendable (DesktopPetNeeds) -> Void
    public var isHungerEnabled: @Sendable () -> Bool

    public init(
        loadNeeds: @escaping @Sendable () -> DesktopPetNeeds?,
        saveNeeds: @escaping @Sendable (DesktopPetNeeds) -> Void,
        isHungerEnabled: @escaping @Sendable () -> Bool
    ) {
        self.loadNeeds = loadNeeds
        self.saveNeeds = saveNeeds
        self.isHungerEnabled = isHungerEnabled
    }

    public static func userDefaults(_ defaults: UserDefaults) -> Self {
        // `UserDefaults` is documented as thread-safe but not declared `Sendable`.
        let defaults = UncheckedSendable(defaults)
        return Self(
            loadNeeds: {
                guard let data = defaults.value.data(forKey: needsKey) else { return nil }
                return try? JSONDecoder().decode(DesktopPetNeeds.self, from: data)
            },
            saveNeeds: { needs in
                guard let data = try? JSONEncoder().encode(needs) else { return }
                defaults.value.set(data, forKey: needsKey)
            },
            isHungerEnabled: {
                defaults.value.object(forKey: hungerEnabledKey) as? Bool ?? true
            }
        )
    }
}

extension DesktopPetNeedsStorage: DependencyKey {
    public static let liveValue = Self.userDefaults(.standard)
    public static let testValue = Self(
        loadNeeds: unimplemented("DesktopPetNeedsStorage.loadNeeds", placeholder: nil),
        saveNeeds: unimplemented("DesktopPetNeedsStorage.saveNeeds"),
        isHungerEnabled: unimplemented("DesktopPetNeedsStorage.isHungerEnabled", placeholder: true)
    )
}

extension DependencyValues {
    public var desktopPetNeedsStorage: DesktopPetNeedsStorage {
        get { self[DesktopPetNeedsStorage.self] }
        set { self[DesktopPetNeedsStorage.self] = newValue }
    }
}
