import ComposableArchitecture
import SwiftUI

/// "Every hour at minute [0]".
struct ScheduleHourlyControls: View {
    @Bindable var store: StoreOf<ScheduleEditorFeature>

    var body: some View {
        HStack(spacing: 8) {
            Text(ScheduleStrings.text("Schedule Every Hour"))
            TextField(ScheduleStrings.text("Schedule Minute"), value: $store.draft.hourlyMinute, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .labelsHidden()
            Stepper(ScheduleStrings.text("Schedule Minute"), value: $store.draft.hourlyMinute, in: 0...59)
                .labelsHidden()
            Text(ScheduleStrings.text("Schedule Minute"))
                .foregroundStyle(.secondary)
        }
    }
}
