import Foundation

public struct ShortcutAppearance: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let iconPNGData: Data?

    public init(id: String, name: String, iconPNGData: Data?) {
        self.id = id
        self.name = name
        self.iconPNGData = iconPNGData
    }
}

public enum ShortcutAppearanceCache {
    private static let key = "shortcutAppearanceCache.v1"
    private static let maximumIconBytes = 64 * 1024

    public static func appearances() -> [ShortcutAppearance] {
        guard let defaults = sharedDefaults(),
              let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([ShortcutAppearance].self, from: data)
        else { return [] }
        return values.map { value in
            guard let icon = value.iconPNGData, icon.count <= maximumIconBytes else { return ShortcutAppearance(id: value.id, name: value.name, iconPNGData: nil) }
            return value
        }
    }

    public static func appearance(named name: String) -> ShortcutAppearance? {
        appearances().first { $0.name == name }
    }

    public static func replace(_ values: [ShortcutAppearance]) {
        let sanitized = values.map { value in
            guard let icon = value.iconPNGData, icon.count <= maximumIconBytes else { return ShortcutAppearance(id: value.id, name: value.name, iconPNGData: nil) }
            return value
        }
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        sharedDefaults()?.set(data, forKey: key)
    }

    private static func sharedDefaults() -> UserDefaults? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty else { return nil }
        return UserDefaults(suiteName: "\(prefix)OnlySwitch.shared")
    }
}
