import RemoteCore
import SwiftUI

/// A schedule in the Schedules tab: what it does, when, and quick Run Now / active controls.
struct SchedulePanelRow: View {
    let schedule: Schedule
    let descriptor: RemoteControlDescriptor?
    let isRunning: Bool
    let compact: Bool
    let send: (SchedulesFeature.Action) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            HStack(spacing: compact ? 8 : 10) {
                ScheduleTargetIcon(icon: descriptor?.icon, size: compact ? 22 : 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(schedule.name)
                        .font((compact ? Font.callout : .body).weight(.medium))
                        .lineLimit(1)
                    Text(verbatim: "\(ScheduleFormatter.actionTitle(schedule.action)) · \(descriptor?.title ?? schedule.target.title)")
                        .lineLimit(1)
                    Text(ScheduleFormatter.triggerSummary(schedule.trigger, calendar: calendar, locale: locale))
                        .lineLimit(1)
                    ScheduleNextRunText(schedule: schedule)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .opacity(schedule.isActive ? 1 : 0.6)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            if case let .failed(message) = schedule.lastOutcome {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(ScheduleFormatter.outcomeSummary(.failed(message)))
                    .accessibilityLabel(ScheduleFormatter.outcomeSummary(.failed(message)))
            }

            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
                    .accessibilityLabel(ScheduleStrings.text("Schedule Run Now"))
            } else {
                Button(ScheduleStrings.text("Schedule Run Now"), systemImage: "play.circle.fill", action: runNow)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .help(ScheduleStrings.text("Schedule Run Now"))
            }

            Toggle(schedule.name, isOn: isActive)
                .toggleStyle(.switch)
                .controlSize(compact ? .mini : .small)
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: "\(ScheduleStrings.text("Schedule Enabled")), \(schedule.name)"))
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 7 : 9)
        .scheduleCard(cornerRadius: compact ? 10 : 12)
    }

    private var isActive: Binding<Bool> {
        Binding(
            get: { schedule.isActive },
            set: { send(.setActive(schedule.id, $0)) }
        )
    }

    private func runNow() {
        send(.runNow(schedule.id))
    }
}
