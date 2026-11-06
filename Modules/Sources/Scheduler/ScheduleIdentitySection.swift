import ComposableArchitecture
import SwiftUI

/// Section ①: target icon, name and the Enabled / Notification switches.
struct ScheduleIdentitySection: View {
    @Bindable var store: StoreOf<ScheduleEditorFeature>

    var body: some View {
        ScheduleSectionCard(number: 1) {
            HStack(alignment: .center, spacing: 16) {
                ScheduleTargetIcon(descriptor: store.catalog.descriptor(for: store.draft.target), size: 44)
                    .padding(6)
                    .scheduleCard(cornerRadius: 10)

                LabeledContent(ScheduleStrings.text("Schedule Name")) {
                    TextField(
                        ScheduleStrings.text("Schedule Name"),
                        text: $store.draft.name,
                        prompt: Text(store.targetTitle ?? "")
                    )
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                }

                VStack(alignment: .trailing, spacing: 8) {
                    Toggle(ScheduleStrings.text("Schedule Enabled"), isOn: $store.draft.isActive)
                    Toggle(
                        ScheduleStrings.text("Schedule Notification"),
                        isOn: $store.draft.notifies.sending(\.notificationToggled)
                    )
                }
                .toggleStyle(.switch)
                .fixedSize()
            }
        }
    }
}
