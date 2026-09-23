import SwiftUI

struct MacPickerView: View {
    let macs: [PairedMac]
    let selectedMacID: UUID?
    let select: (UUID) -> Void

    private var isEnabled: Bool { macs.isEmpty == false }

    var body: some View {
        Menu {
            ForEach(macs) { mac in
                Button {
                    select(mac.id)
                } label: {
                    if mac.id == selectedMacID {
                        Label(mac.displayName, systemImage: "checkmark")
                    } else {
                        Text(mac.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                Text(selectedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(MacPickerSurface(isInteractive: isEnabled))
        .hoverEffect(.highlight)
        .focusable(isEnabled)
        .disabled(!isEnabled)
        .accessibilityLabel("Selected Mac")
        .accessibilityValue(selectedName)
    }

    var selectedName: String {
        macs.first { $0.id == selectedMacID }?.displayName
            ?? String(localized: "No Mac Selected")
    }
}

private struct MacPickerSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(selectionTint, in: pickerShape)
                .background(opaqueSurfaceColor, in: pickerShape)
                .overlay { border }
        } else if #available(iOS 26, *) {
            content
                .background(selectionTint.opacity(0.6), in: pickerShape)
                .overlay { border }
                .glassEffect(
                    .regular.interactive(isInteractive),
                    in: .rect(cornerRadius: 18)
                )
        } else {
            content
                .background(selectionTint, in: pickerShape)
                .background(.thinMaterial, in: pickerShape)
                .overlay { border }
        }
    }

    private var pickerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18)
    }

    private var selectionTint: Color {
        Color.accentColor.opacity(0.06)
    }

    private var border: some View {
        pickerShape.strokeBorder(
            Color.primary.opacity(colorSchemeContrast == .increased ? 0.36 : 0.10),
            lineWidth: colorSchemeContrast == .increased ? 2 : 1
        )
    }

    private var opaqueSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.13)
            : .white
    }
}
