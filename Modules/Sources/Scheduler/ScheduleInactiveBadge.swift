import SwiftUI

/// A small capsule marking a schedule that will not fire.
struct ScheduleInactiveBadge: View {
    var body: some View {
        Text(ScheduleStrings.text("Schedule Inactive"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: .capsule)
    }
}
