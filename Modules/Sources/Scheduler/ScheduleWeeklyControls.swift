import ComposableArchitecture
import SwiftUI

/// "Day of week: [Every Day ▾] [9:00 AM]".
struct ScheduleWeeklyControls: View {
    @Bindable var store: StoreOf<ScheduleEditorFeature>
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: 8) {
            Text(ScheduleStrings.text("Schedule Day Of Week"))
            Menu(ScheduleFormatter.daysSummary(store.draft.weeklyDays, calendar: calendar)) {
                Button(ScheduleStrings.text("Schedule Every Day")) { setDays([]) }
                Button(ScheduleStrings.text("Schedule Weekdays")) { setDays(ScheduleWeekday.weekdays) }
                Button(ScheduleStrings.text("Schedule Weekends")) { setDays(ScheduleWeekday.weekends) }
                Divider()
                ForEach(ScheduleWeekdaySelection.ordered(calendar: calendar), id: \.self) { day in
                    Toggle(calendar.weekdaySymbols[day.rawValue - 1], isOn: dayBinding(day))
                }
            }
            .fixedSize()
            .accessibilityLabel(ScheduleStrings.text("Schedule Day Of Week"))
            .accessibilityValue(ScheduleFormatter.daysSummary(store.draft.weeklyDays, calendar: calendar))

            DatePicker(
                ScheduleStrings.text("Schedule When"),
                selection: timeBinding,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.stepperField)
        }
    }

    private func setDays(_ days: Set<ScheduleWeekday>) {
        store.send(.binding(.set(\.draft.weeklyDays, days)))
    }

    private func dayBinding(_ day: ScheduleWeekday) -> Binding<Bool> {
        Binding(
            get: { ScheduleWeekdaySelection.contains(day, in: store.draft.weeklyDays) },
            set: { _ in setDays(ScheduleWeekdaySelection.toggling(day, in: store.draft.weeklyDays)) }
        )
    }

    /// Bridges `weeklyHour`/`weeklyMinute` to the `Date` the picker edits.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { ScheduleTimeOfDay(hour: store.draft.weeklyHour, minute: store.draft.weeklyMinute).date(in: calendar) },
            set: { date in
                let time = ScheduleTimeOfDay(date: date, calendar: calendar)
                var draft = store.draft
                draft.weeklyHour = time.hour
                draft.weeklyMinute = time.minute
                store.send(.binding(.set(\.draft, draft)))
            }
        )
    }
}
