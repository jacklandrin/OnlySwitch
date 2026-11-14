import DesktopPetSkinKit
import Extensions
import SwiftUI

/// One selectable pet in the appearance list. `skin == nil` is the built-in pet.
struct DesktopPetSkinRow: View {
    let skin: DesktopPetSkin?
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var name: String {
        skin?.name ?? "Desktop Pet Built-in".localized()
    }

    var body: some View {
        HStack(spacing: 12) {
            // Selection and deletion are sibling buttons so each gets its own click and accessibility element.
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    DesktopPetSkinPreviewTile(skin: skin, isAnimating: isSelected || isHovered)
                    Text(name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

            if skin != nil {
                Button("Desktop Pet Edit With AI".localized(), systemImage: "wand.and.stars", action: onEdit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Desktop Pet Edit With AI".localized())
                Button("Desktop Pet Delete Skin".localized(), systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Desktop Pet Delete Skin".localized())
            }
        }
        .padding(6)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
    }
}
