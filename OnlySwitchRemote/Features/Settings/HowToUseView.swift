import SwiftUI

struct HowToUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Mac", systemImage: "desktopcomputer")
                        .font(.headline)
                    Text("Enable iOS Remote Access and start pairing in OnlySwitch on your Mac.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("Pair a Mac", systemImage: "link")
                        .font(.headline)
                    Text("Enter the 12-character code shown on your Mac.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("Settings", systemImage: "checklist")
                        .font(.headline)
                    Text("Choose controls in Settings to add them here.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                        .font(.headline)
                    Text("Tap a dashboard tile to control the selected Mac. Disabled controls explain why they’re unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How to Use")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
        }
    }

    private func close() {
        dismiss()
    }
}
