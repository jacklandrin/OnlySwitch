import Extensions
import SwiftUI

/// Inline warnings for unreadable stored schedules and failed saves.
struct ScheduleNotices: View {
    let isStorageCorrupted: Bool
    let saveError: String?

    var body: some View {
        if isStorageCorrupted || saveError != nil {
            VStack(alignment: .leading, spacing: 6) {
                if isStorageCorrupted {
                    Label(ScheduleStrings.text("Schedule Storage Corrupted"), systemImage: "exclamationmark.triangle.fill")
                }
                if let saveError {
                    Label {
                        Text(verbatim: "Schedule Save Failed %@".localizeWithFormat(arguments: saveError))
                    } icon: {
                        Image(systemName: "exclamationmark.octagon.fill")
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.1))
            .accessibilityElement(children: .combine)
        }
    }
}
