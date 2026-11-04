import RemoteCore
import SwiftUI

/// A schedule in the settings sidebar: icon, name, trigger summary and status badges.
struct ScheduleSidebarRow: View {
    let schedule: Schedule
    let descriptor: RemoteControlDescriptor?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 8) {
            ScheduleTargetIcon(descriptor: descriptor, size: 22)
                .opacity(schedule.isActive ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(schedule.name)
                        .lineLimit(1)
                    if case let .failed(message) = schedule.lastOutcome {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .help(ScheduleFormatter.outcomeSummary(.failed(message)))
                            .accessibilityLabel(ScheduleFormatter.outcomeSummary(.failed(message)))
                    }
                }
                Text(ScheduleFormatter.triggerSummary(schedule.trigger, calendar: calendar, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !schedule.isActive {
                ScheduleInactiveBadge()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
