//
//  ShortcutIconView.swift
//  OnlySwitch
//

import AppKit
import SwiftUI

/// A Shortcut's own icon, as the menu shows it, or the Shortcuts glyph when it isn't known yet.
struct ShortcutIconView: View {
    let pngData: Data?
    var size: CGFloat = 36
    var isActive = true

    var body: some View {
        if let pngData, let image = NSImage(data: pngData) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .opacity(isActive ? 1 : 0.55)
                .accessibilityHidden(true)
        } else {
            ShortcutsGlyph(size: size, isActive: isActive)
        }
    }
}
