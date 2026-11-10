//
//  ShortcutsGlyph.swift
//  OnlySwitch
//

import SwiftUI

/// The Shortcuts glyph in a tinted circle, matching the Evolution gallery icons.
struct ShortcutsGlyph: View {
    var size: CGFloat = 36
    var isActive = true

    var body: some View {
        Image("shortcuts_icon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .padding(size * 0.26)
            .frame(width: size, height: size)
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .background((isActive ? Color.accentColor : .secondary).opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}
