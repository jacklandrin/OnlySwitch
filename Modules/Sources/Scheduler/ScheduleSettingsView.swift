import ComposableArchitecture
import SwiftUI

/// The Settings → Schedules page: a searchable schedule list beside the editor, in the style of Lingon.
public struct ScheduleSettingsView: View {
    @Bindable var store: StoreOf<SchedulesFeature>

    public init(store: StoreOf<SchedulesFeature>) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 0) {
            ScheduleSidebar(store: store)
                .frame(width: 230)
            Divider()
            ScheduleDetail(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: refreshCatalog)
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    private func refreshCatalog() {
        store.send(.refreshCatalog)
    }
}

#if DEBUG
#Preview("Schedules Settings") {
    ScheduleSettingsView(store: SchedulePreviewData.store(selecting: SchedulePreviewData.schedules[0].id))
        .frame(width: 860, height: 600)
}

#Preview("Schedules Settings Empty") {
    ScheduleSettingsView(store: SchedulePreviewData.store(schedules: []))
        .frame(width: 860, height: 600)
}
#endif
