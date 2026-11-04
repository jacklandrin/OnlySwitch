import Extensions
import SwiftUI

/// "Last run: Succeeded" or "Last run: Failed: <reason>".
struct ScheduleLastRunText: View {
    let outcome: ScheduleRunOutcome

    var body: some View {
        Label {
            Text("Schedule Last Run %@".localizeWithFormat(arguments: ScheduleFormatter.outcomeSummary(outcome)))
                .lineLimit(2)
        } icon: {
            Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isFailure ? .red : .green)
        }
    }

    private var isFailure: Bool {
        if case .failed = outcome { true } else { false }
    }
}
