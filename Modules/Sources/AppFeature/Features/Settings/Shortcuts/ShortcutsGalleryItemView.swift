//
//  ShortcutsGalleryItemView.swift
//  OnlySwitch
//

import SwiftUI

/// A gallery card: icon, name, description, author and Add / Added.
struct ShortcutsGalleryItemView: View {
    let item: ShortcutsGalleryItem
    var iconPNGData: Data?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShortcutIconView(pngData: iconPNGData, size: 36)
            Text(item.name)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .help(item.description)
            HStack {
                Text(verbatim: "@\(item.author)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                if item.isInstalled {
                    Button(action: action) {
                        Label("Added".localized(), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .help("Open in Shortcuts".localized())
                } else {
                    Button("Add".localized(), systemImage: "plus", action: action)
                        .evolutionProminentButtonStyle()
                        .controlSize(.small)
                        .disabled(item.linkURL == nil)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .evolutionCard()
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview {
    ShortcutsGalleryItemView(
        item: ShortcutsGalleryItem(
            ShortcutOnMarket(
                name: "Morning Routine",
                link: "https://www.icloud.com/shortcuts/1",
                author: "OnlySwitch",
                description: "Weather, calendar and news."
            )
        ),
        action: {}
    )
    .frame(width: 240)
}
#endif
