import RemoteCore
import SwiftUI

struct ControlSelectionRow: View {
    let descriptor: RemoteControlDescriptor
    let isSelected: Bool
    let showsReorderHandle: Bool
    let selectionChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(isSelected ? "Remove \(descriptor.title) from Dashboard" : "Add \(descriptor.title) to Dashboard", systemImage: isSelected ? "minus.circle.fill" : "plus.circle.fill") {
                selectionChanged(isSelected == false)
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(isSelected ? .red : .green)
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.borderless)
            .accessibilityHint(Text(accessibilityHint))

            HStack(spacing: 12) {
                icon
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.title)
                    if descriptor.isAvailable == false {
                        Text(descriptor.unavailableReason ?? String(localized: "Unavailable on this Mac"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer()
            if showsReorderHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch descriptor.icon {
        case let .systemSymbol(name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        case let .png(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "switch.2")
            }
        }
    }

    private var accessibilityHint: String {
        if descriptor.isAvailable { return String(localized: "Changes dashboard visibility") }
        return descriptor.unavailableReason
            ?? String(localized: "This control can be shown, but it is currently unavailable on the Mac")
    }
}
