import ComposableArchitecture
import SwiftUI

/// Section ③: the trigger kind and its controls.
struct ScheduleWhenSection: View {
    @Bindable var store: StoreOf<ScheduleEditorFeature>

    var body: some View {
        ScheduleSectionCard(number: 3, title: ScheduleStrings.text("Schedule When")) {
            Picker(ScheduleStrings.text("Schedule When"), selection: $store.draft.triggerKind) {
                ForEach(ScheduleTriggerKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Group {
                switch store.draft.triggerKind {
                case .interval:
                    ScheduleIntervalControls(store: store)
                case .hourly:
                    ScheduleHourlyControls(store: store)
                case .weekly:
                    ScheduleWeeklyControls(store: store)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }
}
