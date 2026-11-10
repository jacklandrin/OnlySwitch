//
//  ShortcutsSettingsClient.swift
//  OnlySwitch
//

import Dependencies
import DependenciesMacros
import Foundation
import Switches

/// Every side effect of Settings › Shortcuts: the `shortcuts` CLI, Apple Events,
/// the persisted menu selection, and opening gallery links.
@DependencyClient
struct ShortcutsSettingsClient: Sendable {
    /// Names of the Shortcuts installed on this Mac, in the CLI's order.
    var installedShortcutNames: @Sendable () async throws -> [String]
    /// The saved "show in menu" state, keyed by Shortcut name. `nil` before the first save.
    var shownStates: @Sendable () -> [String: Bool]? = { nil }
    var saveShownStates: @Sendable (_ states: [String: Bool]) -> Void
    /// Tells the menu and widgets that the Shortcut selection changed.
    var notifySettingsChanged: @Sendable () -> Void
    /// Icons already in the shared appearance cache, keyed by Shortcut name.
    var cachedIcons: @Sendable () -> [String: Data] = { [:] }
    /// Reads icons from the Shortcuts app; `nil` when it isn't running.
    var loadIcons: @Sendable (_ names: [String]) async -> [String: Data]?
    /// Replaces the appearance cache used by the menu, widgets and OnlyRemote.
    var saveAppearances: @Sendable (_ appearances: [ShortcutAppearance]) -> Void
    var fetchGallery: @Sendable () async throws -> [ShortcutOnMarket]
    var openURL: @Sendable (URL) -> Void
    /// Opens a Shortcut in the Shortcuts app.
    var showShortcut: @Sendable (_ name: String) async -> Void
}

extension ShortcutsSettingsClient: TestDependencyKey {
    static let testValue = Self()
    static let previewValue = Self(
        installedShortcutNames: { ["Morning Routine", "Resize Images", "Start Focus"] },
        shownStates: { ["Morning Routine": true] },
        saveShownStates: { _ in },
        notifySettingsChanged: {},
        cachedIcons: { [:] },
        loadIcons: { _ in nil },
        saveAppearances: { _ in },
        fetchGallery: {
            [
                ShortcutOnMarket(name: "Morning Routine", link: "https://www.icloud.com/shortcuts/1", author: "OnlySwitch", description: "Weather, calendar and news."),
                ShortcutOnMarket(name: "Clean Downloads", link: "https://www.icloud.com/shortcuts/2", author: "OnlySwitch", description: "Moves old files to the Trash.")
            ]
        },
        openURL: { _ in },
        showShortcut: { _ in }
    )
}

extension DependencyValues {
    var shortcutsSettingsClient: ShortcutsSettingsClient {
        get { self[ShortcutsSettingsClient.self] }
        set { self[ShortcutsSettingsClient.self] = newValue }
    }
}
