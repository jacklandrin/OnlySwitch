import ComposableArchitecture
import SwiftUI

/// Section ②: what to run and which action to apply.
struct ScheduleRunSection: View {
    @Bindable var store: StoreOf<ScheduleEditorFeature>

    var body: some View {
        ScheduleSectionCard(number: 2, title: ScheduleStrings.text("Schedule Run")) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(ScheduleStrings.text("Schedule Target"))
                        .gridColumnAlignment(.trailing)
                    ScheduleTargetPicker(store: store)
                }
                GridRow {
                    Text(ScheduleStrings.text("Schedule Action"))
                    Picker(ScheduleStrings.text("Schedule Action"), selection: $store.draft.action) {
                        ForEach(store.allowedActions, id: \.self) { action in
                            Text(ScheduleFormatter.actionTitle(action)).tag(action)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if store.targetIsUnavailable {
                Label(ScheduleStrings.text("Schedule Target Unavailable"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
    }
}
