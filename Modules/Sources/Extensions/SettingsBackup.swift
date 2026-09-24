//
//  SettingsBackup.swift
//  OnlySwitch
//

import Foundation

public enum SettingsBackupError: LocalizedError, Equatable {
    case invalidFile
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Invalid Settings Backup File".localized()
        case .unsupportedVersion:
            return "This backup was made by a newer version of Only Switch".localized()
        }
    }
}

public struct RadioStationBackup: Equatable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// Evolution items run shell commands, so they are kept apart from plain preferences
/// and must be explicitly accepted by the user before import.
public struct EvolutionBackup: Equatable, Sendable {
    public static let preExecutionKey = "pre-execution"
    public static let commandKeys = [
        "id", "name", "itemType", "iconName",
        "singleCommand", "singleCommandType",
        "turnOnCommand", "turnOnCommandType",
        "turnOffCommand", "turnOffCommandType",
        "statusCommand", "statusCommandType", "trueCondition",
        "privilegedOperationIdentifier",
    ]

    public var preExecution: String?
    public var commands: [[String: String]]

    public init(preExecution: String?, commands: [[String: String]]) {
        self.preExecution = preExecution
        self.commands = commands.map { $0.filter { Self.commandKeys.contains($0.key) } }
    }

    public var isEmpty: Bool {
        commands.isEmpty && (preExecution ?? "").isEmpty
    }
}

/// On-disk format of a settings backup: an XML property list.
/// Values read from a file are untrusted; only allowlisted keys survive decoding.
public struct SettingsBackup {
    public static let formatVersion = 1
    /// Keys written by libraries/AppKit rather than the registry: keyboard shortcuts and
    /// the menu bar status item positions.
    public static let exportablePrefixes = ["KeyboardShortcuts_", "NSStatusItem Preferred Position"]

    public var preferences: [String: Any]
    public var sharedPreferences: [String: Any]
    public var radioStations: [RadioStationBackup]
    public var evolution: EvolutionBackup

    public init(
        preferences: [String: Any],
        sharedPreferences: [String: Any],
        radioStations: [RadioStationBackup],
        evolution: EvolutionBackup
    ) {
        self.preferences = preferences.filter { Self.isExportablePreference($0.key) }
        self.sharedPreferences = sharedPreferences.filter { Self.isSharedPreference($0.key) }
        self.radioStations = radioStations
        self.evolution = evolution
    }

    public static func isExportablePreference(_ key: String) -> Bool {
        UserDefaults.Key.exportableKeys.contains(key) || exportablePrefixes.contains { key.hasPrefix($0) }
    }

    public static func isSharedPreference(_ key: String) -> Bool {
        UserDefaults.Key.sharedExportableKeys.contains(key)
    }

    public static func collectPreferences(from defaults: UserDefaults) -> [String: Any] {
        defaults.dictionaryRepresentation().filter { isExportablePreference($0.key) }
    }

    public static func collectSharedPreferences(from defaults: UserDefaults) -> [String: Any] {
        var values: [String: Any] = [:]
        for key in UserDefaults.Key.sharedExportableKeys {
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        return values
    }

    /// Makes `defaults` match the backup: backed-up values are written, and allowed keys the
    /// backup doesn't contain (left at their default when exported) are reset to their default.
    public static func replace(
        _ values: [String: Any],
        in defaults: UserDefaults,
        isAllowed: (String) -> Bool
    ) {
        for key in defaults.dictionaryRepresentation().keys where isAllowed(key) && values[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in values where isAllowed(key) {
            defaults.set(value, forKey: key)
        }
    }

    public func encoded() throws -> Data {
        var evolutionRoot: [String: Any] = ["commands": evolution.commands]
        if let preExecution = evolution.preExecution {
            evolutionRoot["preExecution"] = preExecution
        }
        let root: [String: Any] = [
            "formatVersion": Self.formatVersion,
            "preferences": preferences,
            "sharedPreferences": sharedPreferences,
            "radioStations": radioStations.map { ["title": $0.title, "url": $0.url] },
            "evolution": evolutionRoot,
        ]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    public init(data: Data) throws {
        guard
            let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let version = root["formatVersion"] as? Int
        else {
            throw SettingsBackupError.invalidFile
        }
        guard version <= Self.formatVersion else {
            throw SettingsBackupError.unsupportedVersion(version)
        }

        let stations = (root["radioStations"] as? [[String: String]] ?? []).compactMap { entry -> RadioStationBackup? in
            guard let title = entry["title"], let url = entry["url"] else { return nil }
            return RadioStationBackup(title: title, url: url)
        }
        let evolutionRoot = root["evolution"] as? [String: Any] ?? [:]

        self.init(
            preferences: root["preferences"] as? [String: Any] ?? [:],
            sharedPreferences: root["sharedPreferences"] as? [String: Any] ?? [:],
            radioStations: stations,
            evolution: EvolutionBackup(
                preExecution: evolutionRoot["preExecution"] as? String,
                commands: evolutionRoot["commands"] as? [[String: String]] ?? []
            )
        )
    }
}
