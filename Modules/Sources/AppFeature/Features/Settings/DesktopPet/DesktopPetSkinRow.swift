import DesktopPetSkinKit
import Extensions
import SwiftUI

/// One selectable pet in the appearance list. `skin == nil` is the built-in pet.
struct DesktopPetSkinRow: View {
    let skin: DesktopPetSkin?
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var name: String {
        skin?.name ?? "Desktop Pet Built-in".localized()
    }

    var body: some View {
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
                if skin != nil {
                    Button("Desktop Pet Delete Skin".localized(), systemImage: "trash", role: .destructive, action: onDelete)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Desktop Pet Delete Skin".localized())
                }
            }
            .padding(6)
            .background(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
