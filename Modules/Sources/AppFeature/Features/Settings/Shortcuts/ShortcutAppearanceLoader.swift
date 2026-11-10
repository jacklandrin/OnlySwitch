//
//  ShortcutAppearanceLoader.swift
//  OnlySwitch
//

import AppKit
import Defines
import Extensions
import OSLog
import Switches

/// Reads Shortcut icons through Apple Events and keeps `ShortcutAppearanceCache`
/// (used by the menu, widgets and OnlyRemote) up to date.
@MainActor
enum ShortcutAppearanceLoader {
    /// Icons from the shared cache, keyed by Shortcut name. Only shown Shortcuts are cached.
    nonisolated static func cachedIcons() -> [String: Data] {
        var icons: [String: Data] = [:]
        for appearance in ShortcutAppearanceCache.appearances() {
            if let data = appearance.iconPNGData { icons[appearance.name] = data }
        }
        return icons
    }

    /// The icons of `names`, or `nil` when the Shortcuts app isn't running.
    ///
    /// Apple Events launch their target application by default, so nothing is read
    /// while Shortcuts is closed; opening OnlySwitch never opens Shortcuts as a side effect.
    /// Each lookup is a synchronous Apple Event, so the loop yields between them to keep the UI responsive.
    static func icons(for names: [String]) async -> [String: Data]? {
        guard isShortcutsRunning else { return nil }
        var icons: [String: Data] = [:]
        for name in names {
            guard !Task.isCancelled else { return nil }
            if let data = iconPNGData(named: name) { icons[name] = data }
            await Task.yield()
        }
        return icons
    }

    /// Re-reads the icons of the shown Shortcuts into the shared cache.
    static func refresh(for names: [String]) async {
        guard !names.isEmpty else {
            save([])
            return
        }
        guard let icons = await icons(for: names) else { return }
        save(names.compactMap { name in
            icons[name].map { ShortcutAppearance(id: name, name: name, iconPNGData: $0) }
        })
    }

    /// Replaces the shared cache and tells the menu, unless nothing changed.
    nonisolated static func save(_ appearances: [ShortcutAppearance]) {
        guard ShortcutAppearanceCache.appearances() != appearances else { return }
        ShortcutAppearanceCache.replace(appearances)
        NotificationCenter.default.post(name: .changeSettings, object: nil)
    }

    private static var isShortcutsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.shortcuts").isEmpty
    }

    private static func iconPNGData(named name: String) -> Data? {
        let escapedName = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application id \"com.apple.shortcuts\" to get icon of shortcut \"\(escapedName)\""
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let descriptor = script.executeAndReturnError(&error)
        guard
            let image = NSImage(data: descriptor.data),
            let resized = image.resizeMaintainingAspectRatio(withSize: NSSize(width: 64, height: 64)),
            let pngData = resized.pngData,
            pngData.count <= 64 * 1024
        else {
            if let error { Logger.settings.error("Unable to read Shortcuts icon for \(name): \(error)") }
            return nil
        }
        return pngData
    }
}
