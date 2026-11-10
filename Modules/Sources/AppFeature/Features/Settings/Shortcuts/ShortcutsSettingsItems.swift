//
//  ShortcutsSettingsItems.swift
//  OnlySwitch
//

import Foundation

/// A Shortcut installed on this Mac and whether it's shown in the OnlySwitch menu.
struct InstalledShortcut: Equatable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    var isShown: Bool
}

/// A community Shortcut from the gallery, identified by its iCloud link.
struct ShortcutsGalleryItem: Equatable, Identifiable, Sendable {
    var id: String { link }
    let name: String
    let link: String
    let author: String
    let description: String
    var isInstalled = false

    init(_ shortcut: ShortcutOnMarket, isInstalled: Bool = false) {
        name = shortcut.name
        link = shortcut.link
        author = shortcut.author
        description = shortcut.description
        self.isInstalled = isInstalled
    }

    /// Only `https` links are opened, so a tampered gallery can't launch other URL schemes.
    var linkURL: URL? {
        guard let url = URL(string: link), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}
