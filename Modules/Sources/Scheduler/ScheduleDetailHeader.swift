import ComposableArchitecture
import SwiftUI

/// The detail title bar with the ▶ Run Now button for the saved schedule being edited.
struct ScheduleDetailHeader: View {
    let store: StoreOf<SchedulesFeature>

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(ScheduleStrings.text("Schedule Run Now"))
            }
            Button(ScheduleStrings.text("Schedule Run Now"), systemImage: "play.fill", action: runNow)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title3)
                .help(ScheduleStrings.text("Schedule Run Now"))
                .disabled(scheduleID == nil || isRunning)
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    /// The saved schedule shown in the editor; `nil` while drafting a new one.
    private var scheduleID: Schedule.ID? {
        store.editor?.original?.id
    }

    private var isRunning: Bool {
        scheduleID.map(store.running.contains) ?? false
    }

    private var title: String {
        if let original = store.editor?.original { return original.name }
        return ScheduleStrings.text(store.editor == nil ? "Schedules" : "Schedule New")
    }

    private func runNow() {
        guard let scheduleID else { return }
        store.send(.runNow(scheduleID))
    }
}
