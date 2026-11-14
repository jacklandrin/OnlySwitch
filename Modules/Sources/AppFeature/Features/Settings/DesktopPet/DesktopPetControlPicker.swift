import ComposableArchitecture
import Extensions
import RemoteCore
import Scheduler
import SwiftUI

/// A button showing the chosen control that opens the grouped, searchable control list shared with Schedules.
struct DesktopPetControlPicker: View {
    @Bindable var store: StoreOf<DesktopPetSettingsFeature>
    @State private var isPresented = false

    var body: some View {
        Button(action: togglePopover) {
            HStack(spacing: 6) {
                ScheduleTargetIcon(descriptor: store.targetDescriptor, size: 16)
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(store.target == nil ? .secondary : .primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 200, maxWidth: 280)
        }
        .accessibilityLabel("Desktop Pet Control".localized())
        .accessibilityValue(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScheduleTargetList(
                groups: ScheduleTargetGroups.make(catalog: store.catalog, search: store.targetSearch),
                selection: store.target?.controlID,
                search: $store.targetSearch,
                select: select
            )
        }
    }

    private var title: String {
        store.targetTitle ?? "Desktop Pet Choose Control".localized()
    }

    private func togglePopover() {
        isPresented.toggle()
    }

    private func select(_ id: RemoteControlID) {
        store.send(.targetSelected(id))
        isPresented = false
    }
}
