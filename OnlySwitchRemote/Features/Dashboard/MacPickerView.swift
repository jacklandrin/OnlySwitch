import SwiftUI

struct MacPickerView: View {
    let macs: [PairedMac]
    let selectedMacID: UUID?
    let select: (UUID) -> Void

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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selected Mac")
        .accessibilityValue(selectedName)
    }

    var selectedName: String {
        macs.first { $0.id == selectedMacID }?.displayName
            ?? String(localized: "No Mac Selected")
    }
}
