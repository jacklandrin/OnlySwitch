import RemoteCore
import SwiftUI

/// The popover content of `ScheduleTargetPicker`.
struct ScheduleTargetList: View {
    let groups: [ScheduleTargetGroup]
    let selection: RemoteControlID?
    @Binding var search: String
    let select: (RemoteControlID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScheduleSearchField(prompt: ScheduleStrings.text("Schedule Search"), text: $search)
                .padding(10)

            if groups.isEmpty {
                ContentUnavailableView.search(text: search)
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section(ScheduleStrings.text(group.kind.titleKey)) {
                            ForEach(group.descriptors) { descriptor in
                                ScheduleTargetRow(
                                    descriptor: descriptor,
                                    isSelected: descriptor.id == selection,
                                    select: select
                                )
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 320, height: 380)
    }
}
