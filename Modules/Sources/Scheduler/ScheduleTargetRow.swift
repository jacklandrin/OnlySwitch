import RemoteCore
import SwiftUI

/// One catalog control in the target popover; unavailable controls are disabled and show why.
struct ScheduleTargetRow: View {
    let descriptor: RemoteControlDescriptor
    let isSelected: Bool
    let select: (RemoteControlID) -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 8) {
                ScheduleTargetIcon(icon: descriptor.icon, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(descriptor.title)
                        .lineLimit(1)
                    if !descriptor.isAvailable, let reason = descriptor.unavailableReason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!descriptor.isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose() {
        select(descriptor.id)
    }
}
