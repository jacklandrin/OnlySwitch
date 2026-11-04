import ComposableArchitecture
import RemoteCore
import SwiftUI

/// A button showing the chosen target that opens a searchable, grouped list of catalog controls.
struct ScheduleTargetPicker: View {
    @Bindable var store: StoreOf<ScheduleEditorFeature>
    @State private var isPresented = false

    var body: some View {
        Button(action: togglePopover) {
            HStack(spacing: 6) {
                ScheduleTargetIcon(descriptor: selectedDescriptor, size: 16)
                Text(store.draft.target?.title ?? ScheduleStrings.text("Schedule Choose Target"))
                    .lineLimit(1)
                    .foregroundStyle(store.draft.target == nil ? .secondary : .primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 200, maxWidth: 280)
        }
        .accessibilityLabel(ScheduleStrings.text("Schedule Target"))
        .accessibilityValue(store.draft.target?.title ?? ScheduleStrings.text("Schedule Choose Target"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScheduleTargetList(
                groups: ScheduleTargetGroups.make(catalog: store.catalog, search: store.targetSearch),
                selection: store.draft.target?.controlID,
                search: $store.targetSearch,
                select: select
            )
        }
    }

    private var selectedDescriptor: RemoteControlDescriptor? {
        store.catalog.descriptor(for: store.draft.target)
    }

    private func togglePopover() {
        isPresented.toggle()
    }

    private func select(_ id: RemoteControlID) {
        store.send(.targetSelected(id))
        isPresented = false
    }
}
