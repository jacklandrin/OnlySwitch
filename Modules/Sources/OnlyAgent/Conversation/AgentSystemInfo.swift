//
//  AgentSystemInfo.swift
//  Modules
//

import CoreGraphics
import Darwin
import Foundation

/// A snapshot of the Mac that is given to the model on every turn so scripts
/// match this computer (OS version, chip, displays, language, appearance).
///
/// Privacy: it deliberately excludes the user name, computer name, serial
/// number and any other identifier of the person or the device.
public struct AgentSystemInfo: Equatable, Sendable {
    public var osVersion: String
    public var osBuild: String?
    public var architecture: String?
    public var modelIdentifier: String?
    public var memoryGB: Int?
    public var language: String?
    public var region: String?
    public var displayCount: Int?
    public var isDarkMode: Bool?
    public var showsHiddenFiles: Bool?
    public var dockAutohides: Bool?
    /// Absolute path of the `brew` executable, when Homebrew is installed.
    public var homebrewPath: String?

    public init(
        osVersion: String = "",
        osBuild: String? = nil,
        architecture: String? = nil,
        modelIdentifier: String? = nil,
        memoryGB: Int? = nil,
        language: String? = nil,
        region: String? = nil,
        displayCount: Int? = nil,
        isDarkMode: Bool? = nil,
        showsHiddenFiles: Bool? = nil,
        dockAutohides: Bool? = nil,
        homebrewPath: String? = nil
    ) {
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.architecture = architecture
        self.modelIdentifier = modelIdentifier
        self.memoryGB = memoryGB
        self.language = language
        self.region = region
        self.displayCount = displayCount
        self.isDarkMode = isDarkMode
        self.showsHiddenFiles = showsHiddenFiles
        self.dockAutohides = dockAutohides
        self.homebrewPath = homebrewPath
    }

    /// One bullet per known fact; unknown values are omitted.
    public var promptDescription: String {
        var lines: [String] = []
        if !osVersion.isEmpty {
            lines.append("- macOS \(osVersion)" + (osBuild.map { " (build \($0))" } ?? ""))
        }
        if let architecture {
            let chip = architecture.hasPrefix("arm") ? "Apple Silicon" : architecture.hasPrefix("x86") ? "Intel" : architecture
            lines.append("- Chip: \(chip) (\(architecture))")
        }
        if let modelIdentifier {
            lines.append("- Mac model: \(modelIdentifier)")
        }
        if let memoryGB {
            lines.append("- Memory: \(memoryGB) GB")
        }
        if let language {
            lines.append("- Preferred language: \(language)")
        }
        if let region {
            lines.append("- Region: \(region)")
        }
        if let displayCount {
            lines.append("- Displays: \(displayCount)")
        }
        if let isDarkMode {
            lines.append("- Appearance: \(isDarkMode ? "Dark" : "Light")")
        }
        if let showsHiddenFiles {
            lines.append("- Finder shows hidden files: \(showsHiddenFiles ? "Yes" : "No")")
        }
        if let dockAutohides {
            lines.append("- Dock auto-hide: \(dockAutohides ? "On" : "Off")")
        }
        if let homebrewPath {
            lines.append("- Homebrew: \(homebrewPath)")
        }
        return lines.joined(separator: "\n")
    }
}

extension AgentSystemInfo {
    /// Reads the current values. Every source is cheap, non-interactive and
    /// needs no permission prompt.
    static func current() -> AgentSystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var displayCount: UInt32 = 0
        let displays: Int? = CGGetActiveDisplayList(0, nil, &displayCount) == .success ? Int(displayCount) : nil
        let memory = ProcessInfo.processInfo.physicalMemory
        return AgentSystemInfo(
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            osBuild: sysctlString("kern.osversion"),
            architecture: sysctlString("hw.machine"),
            modelIdentifier: sysctlString("hw.model"),
            memoryGB: memory > 0 ? Int((Double(memory) / 1_073_741_824).rounded()) : nil,
            language: Locale.preferredLanguages.first,
            region: Locale.current.region?.identifier,
            displayCount: displays,
            isDarkMode: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark",
            showsHiddenFiles: preferenceBool(UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "AppleShowAllFiles")) ?? false,
            dockAutohides: preferenceBool(UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "autohide")) ?? false,
            homebrewPath: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
                .first { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    /// Preferences written with `defaults write` may be booleans, numbers or
    /// strings such as "YES"/"TRUE"/"1".
    static func preferenceBool(_ raw: Any?) -> Bool? {
        switch raw {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["1", "yes", "true"].contains(value.lowercased())
        default:
            return nil
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
