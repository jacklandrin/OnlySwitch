//
//  ShortcutsSettingsClient+Live.swift
//  OnlySwitch
//

import AppKit
import Dependencies
import Defines
import Extensions
import Networking
import OSLog
import Switches

extension ShortcutsSettingsClient: DependencyKey {
    static var liveValue: Self {
        Self(
            installedShortcutNames: {
                let output = try await ShorcutsCMD.getList.runAppleScript(isShellCMD: true)
                return output
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .filter { !$0.isEmpty }
            },
            shownStates: { Preferences.shared.shortcutsDic },
            saveShownStates: { Preferences.shared.shortcutsDic = $0 },
            notifySettingsChanged: {
                NotificationCenter.default.post(name: .changeSettings, object: nil)
            },
            cachedIcons: { ShortcutAppearanceLoader.cachedIcons() },
            loadIcons: { names in await ShortcutAppearanceLoader.icons(for: names) },
            saveAppearances: { ShortcutAppearanceLoader.save($0) },
            fetchGallery: {
                do {
                    return try await GitHubPresenter.shared.requestShortcutsJson(type: [ShortcutOnMarket].self)
                } catch {
                    Logger.settings.warning("Shortcuts gallery request failed, using the bundled list: \(error.localizedDescription)")
                    guard let url = Bundle.main.url(forResource: "ShortcutsMarket", withExtension: "json") else {
                        Logger.settings.error("ShortcutsMarket.json not found")
                        throw error
                    }
                    return try JSONDecoder().decode([ShortcutOnMarket].self, from: Data(contentsOf: url))
                }
            },
            openURL: { url in
                Task { @MainActor in NSWorkspace.shared.open(url) }
            },
            showShortcut: { name in
                _ = try? await ShorcutsCMD.showShortcut(name: name).runAppleScript(isShellCMD: true)
            }
        )
    }
}
