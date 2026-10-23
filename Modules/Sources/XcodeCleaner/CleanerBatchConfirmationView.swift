#if os(macOS)
import SwiftUI
import Extensions

/// The reducer freezes this sheet's rows and validates its host/token before any cleanup.
struct CleanerBatchConfirmationView: View {
    let items: [CleanerItem]
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Xcode Cleaner Confirm Batch".localizeWithFormat(arguments: items.count), systemImage: "exclamationmark.triangle")
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.category == .simulatorDevice || item.category == .simulatorRuntime ? item.title : item.title.localized())
                                .font(.body.weight(.medium))
                            Text(item.runtimeName ?? item.runtimeIdentifier ?? item.detail)
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    if items.contains(where: { $0.category == .simulatorDevice }) { warning("Xcode Cleaner Confirm Device") }
                    if items.contains(where: { $0.category == .simulatorRuntime }) { warning("Xcode Cleaner Confirm Runtime") }
                    if items.contains(where: { $0.category == .deviceSupport }) { warning("Xcode Cleaner Confirm Support") }
                }
            }.frame(maxHeight: 280)
            HStack {
                Spacer()
                Button("Cancel".localized(), role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Xcode Cleaner Delete".localized(), role: .destructive, action: confirm).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(minWidth: 320, idealWidth: 420, maxWidth: 520)
    }
    private func warning(_ key: String) -> some View { Text(key.localized()).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
#endif
