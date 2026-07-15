import SwiftUI

struct MacPickerView: View {
    let macs: [PairedMac]
    let selectedMacID: UUID?
    let select: (UUID) -> Void

    var body: some View {
        Picker("Selected Mac", selection: selection) {
            ForEach(macs) { mac in
                Text(mac.displayName).tag(mac.id as UUID?)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityLabel("Selected Mac")
        .accessibilityValue(selectedName)
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { selectedMacID },
            set: { if let id = $0 { select(id) } }
        )
    }

    private var selectedName: String {
        macs.first { $0.id == selectedMacID }?.displayName ?? String(localized: "No Mac Selected")
    }
}
