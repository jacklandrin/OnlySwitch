import ComposableArchitecture
import SwiftUI

/// The right side of the settings page: notices, the header with ▶ Run Now, and the editor or an empty state.
struct ScheduleDetail: View {
    let store: StoreOf<SchedulesFeature>

    var body: some View {
        VStack(spacing: 0) {
            ScheduleDetailHeader(store: store)
            Divider()
            ScheduleNotices(isStorageCorrupted: store.isStorageCorrupted, saveError: store.saveError)

            if let editor = store.scope(state: \.editor, action: \.editor.presented) {
                ScheduleEditorView(store: editor, schedule: savedSchedule)
            } else {
                ContentUnavailableView {
                    Label(ScheduleStrings.text("Schedule Empty"), systemImage: ScheduleTargetIcon.fallbackSymbol)
                } description: {
                    Text(ScheduleStrings.text("Schedule Empty Message"))
                } actions: {
                    Button(ScheduleStrings.text("Schedule New"), action: add)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var savedSchedule: Schedule? {
        store.editor?.original.flatMap { store.schedules[id: $0.id] }
    }

    private func add() {
        store.send(.addTapped)
    }
}
