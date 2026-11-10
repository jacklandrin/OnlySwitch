//
//  AgentSuggestion.swift
//  Modules
//

/// Starter prompts for an empty conversation, chosen from the Mac's current
/// state so a suggestion always describes a change (never "turn on dark mode"
/// while dark mode is already on). Raw values are localization keys.
public enum AgentSuggestion: String, Equatable, Sendable, CaseIterable {
    case turnOnDarkMode = "Turn on dark mode"
    case turnOnLightMode = "Turn on light mode"
    case upgradeHomebrew = "Upgrade Homebrew packages"
    case autoHideDock = "Automatically hide the Dock"
    case alwaysShowDock = "Always show the Dock"
    case showHiddenFiles = "Show hidden files in Finder"
    case hideHiddenFiles = "Hide hidden files in Finder"

    /// Unknown states fall back to the macOS defaults (light mode, Dock
    /// always shown, hidden files hidden).
    public static func make(for info: AgentSystemInfo) -> [AgentSuggestion] {
        var suggestions: [AgentSuggestion] = [info.isDarkMode == true ? .turnOnLightMode : .turnOnDarkMode]
        if info.homebrewPath != nil {
            suggestions.append(.upgradeHomebrew)
        }
        suggestions.append(info.dockAutohides == true ? .alwaysShowDock : .autoHideDock)
        suggestions.append(info.showsHiddenFiles == true ? .hideHiddenFiles : .showHiddenFiles)
        return suggestions
    }
}
