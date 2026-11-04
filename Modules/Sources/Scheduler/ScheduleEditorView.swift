import ComposableArchitecture
import SwiftUI

/// The detail pane of the Schedules settings page: ① identity, ② Run, ③ When, then the save footer.
struct ScheduleEditorView: View {
    let store: StoreOf<ScheduleEditorFeature>
    /// The saved schedule as the engine currently sees it (fresher than `store.original`).
    let schedule: Schedule?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScheduleIdentitySection(store: store)
                ScheduleRunSection(store: store)
                ScheduleWhenSection(store: store)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                ScheduleEditorFooter(store: store, schedule: schedule)
            }
            .background(.bar)
        }
    }
}

#if DEBUG
#Preview("Editor") {
    ScheduleEditorView(
        store: Store(
            initialState: ScheduleEditorFeature.State(
                original: SchedulePreviewData.schedules[0],
                catalog: SchedulePreviewData.catalog
            )
        ) {
            ScheduleEditorFeature()
        },
        schedule: SchedulePreviewData.schedules[0]
    )
    .frame(width: 620, height: 560)
}
#endif
