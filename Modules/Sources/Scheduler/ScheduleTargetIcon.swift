import AppKit
import RemoteCore
import SwiftUI

/// A catalog control's icon, falling back to a calendar glyph when the control is unknown or its image is unreadable.
struct ScheduleTargetIcon: View {
    let icon: RemoteControlDescriptor.Icon?
    var size: CGFloat = 24

    static let fallbackSymbol = "calendar.badge.clock"

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch icon {
        case let .png(data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                symbol(Self.fallbackSymbol)
            }
        case let .systemSymbol(name):
            symbol(name)
        case nil:
            symbol(Self.fallbackSymbol)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .foregroundStyle(.tint)
            .padding(size * 0.1)
    }
}

extension Array where Element == RemoteControlDescriptor {
    /// The catalog entry a schedule targets, if it is still in the catalog.
    func descriptor(for target: ScheduleTarget?) -> RemoteControlDescriptor? {
        guard let target else { return nil }
        return first { $0.id == target.controlID }
    }
}
