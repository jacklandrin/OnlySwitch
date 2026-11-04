import ComposableArchitecture
import SwiftUI

/// Next run, last outcome, validation issues and the Discard / Save buttons.
struct ScheduleEditorFooter: View {
    let store: StoreOf<ScheduleEditorFeature>
    /// The saved schedule as the engine currently sees it, for next-run and last-run info.
    let schedule: Schedule?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.issues.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.issues, id: \.self) { issue in
                        Label(ScheduleFormatter.issueMessage(issue), systemImage: "exclamationmark.circle.fill")
                    }
                }
                .font(.callout)
                .foregroundStyle(.red)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let schedule {
                        ScheduleNextRunText(schedule: schedule)
                        if let outcome = schedule.lastOutcome {
                            ScheduleLastRunText(outcome: outcome)
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button(ScheduleStrings.text("Schedule Discard Changes"), action: discard)
                    .disabled(!store.isDirty)
                Button(ScheduleStrings.text("Schedule Save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.isDirty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func discard() {
        store.send(.discardTapped)
    }

    private func save() {
        store.send(.saveTapped)
    }
}
