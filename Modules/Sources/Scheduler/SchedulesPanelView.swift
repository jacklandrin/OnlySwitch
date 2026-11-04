import ComposableArchitecture
import SwiftUI

/// The Schedules tab of the OnlySwitch list and OnlyControl. Lays out without its own scroll view
/// so it can sit inside the parent panel's `ScrollView`.
public struct SchedulesPanelView: View {
    let store: StoreOf<SchedulesFeature>
    let compact: Bool
    let openSettings: () -> Void

    public init(store: StoreOf<SchedulesFeature>, compact: Bool = false, openSettings: @escaping () -> Void) {
        self.store = store
        self.compact = compact
        self.openSettings = openSettings
    }

    public var body: some View {
        if store.schedules.isEmpty {
            ContentUnavailableView {
                Label(ScheduleStrings.text("Schedule Empty"), systemImage: ScheduleTargetIcon.fallbackSymbol)
            } description: {
                Text(ScheduleStrings.text("Schedule Empty Message"))
            } actions: {
                Button(ScheduleStrings.text("Schedule Manage"), action: openSettings)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, compact ? 8 : 16)
        } else {
            LazyVStack(spacing: compact ? 6 : 8) {
                ForEach(store.schedules) { schedule in
                    SchedulePanelRow(
                        schedule: schedule,
                        descriptor: store.catalog.descriptor(for: schedule.target),
                        isRunning: store.running.contains(schedule.id),
                        compact: compact,
                        send: send
                    )
                }

                Button(ScheduleStrings.text("Schedule Manage"), systemImage: "gearshape", action: openSettings)
                    .buttonStyle(.borderless)
                    .font(compact ? .caption : .callout)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
            }
        }
    }

    private func send(_ action: SchedulesFeature.Action) {
        store.send(action)
    }
}

#if DEBUG
#Preview("Panel") {
    ScrollView {
        SchedulesPanelView(store: SchedulePreviewData.store(), openSettings: {})
            .padding()
    }
    .frame(width: 420, height: 420)
}

#Preview("Panel Compact") {
    ScrollView {
        SchedulesPanelView(store: SchedulePreviewData.store(), compact: true, openSettings: {})
            .padding(10)
    }
    .frame(width: 300, height: 420)
}

#Preview("Panel Empty") {
    SchedulesPanelView(store: SchedulePreviewData.store(schedules: []), compact: true, openSettings: {})
        .frame(width: 300)
}
#endif
