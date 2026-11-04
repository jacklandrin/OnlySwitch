import ComposableArchitecture
import SwiftUI

/// "Repeat interval: [10] [minutes]".
struct ScheduleIntervalControls: View {
    @Bindable var store: StoreOf<ScheduleEditorFeature>

    var body: some View {
        HStack(spacing: 8) {
            Text(ScheduleStrings.text("Schedule Repeat Interval"))
            TextField(ScheduleStrings.text("Schedule Repeat Interval"), value: $store.draft.intervalValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .labelsHidden()
            Stepper(ScheduleStrings.text("Schedule Repeat Interval"), value: $store.draft.intervalValue, in: 1...ScheduleCalendar.maximumIntervalSeconds)
                .labelsHidden()
            Picker(ScheduleStrings.text("Schedule Repeat Interval"), selection: $store.draft.intervalUnit) {
                ForEach(ScheduleIntervalUnit.allCases, id: \.self) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
