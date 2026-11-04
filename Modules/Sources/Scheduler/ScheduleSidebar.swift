import ComposableArchitecture
import SwiftUI

/// Search, the schedule list and the + / − buttons.
struct ScheduleSidebar: View {
    @Bindable var store: StoreOf<SchedulesFeature>

    var body: some View {
        VStack(spacing: 0) {
            ScheduleSearchField(prompt: ScheduleStrings.text("Schedule Search"), text: $store.searchText)
                .padding(10)

            List(selection: $store.selection.sending(\.select)) {
                ForEach(store.filteredSchedules) { schedule in
                    ScheduleSidebarRow(
                        schedule: schedule,
                        descriptor: store.catalog.descriptor(for: schedule.target)
                    )
                    .tag(schedule.id)
                    .contextMenu {
                        Button(ScheduleStrings.text("Schedule Run Now"), systemImage: "play.fill") {
                            store.send(.runNow(schedule.id))
                        }
                        .disabled(store.running.contains(schedule.id))
                        Divider()
                        Button(ScheduleStrings.text("Schedule Delete"), systemImage: "trash", role: .destructive) {
                            store.send(.deleteTapped(schedule.id))
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if store.filteredSchedules.isEmpty, !store.searchText.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button(ScheduleStrings.text("Schedule New"), systemImage: "plus", action: add)
                    .help(ScheduleStrings.text("Schedule New"))
                Button(ScheduleStrings.text("Schedule Delete"), systemImage: "minus", action: delete)
                    .help(ScheduleStrings.text("Schedule Delete"))
                    .disabled(store.selection == nil)
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        // A content-coloured column, so the list doesn't blend into the Settings sidebar beside it.
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func add() {
        store.send(.addTapped)
    }

    private func delete() {
        guard let id = store.selection else { return }
        store.send(.deleteTapped(id))
    }
}
