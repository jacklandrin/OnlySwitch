import RemoteCore
import SwiftUI

struct ControlSelectionRow: View {
    let descriptor: RemoteControlDescriptor
    let isSelected: Bool
    let selectionChanged: (Bool) -> Void
    @State private var isOn: Bool

    init(
        descriptor: RemoteControlDescriptor,
        isSelected: Bool,
        selectionChanged: @escaping (Bool) -> Void
    ) {
        self.descriptor = descriptor
        self.isSelected = isSelected
        self.selectionChanged = selectionChanged
        _isOn = State(initialValue: isSelected)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
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
        }
        .onChange(of: isSelected) { _, newValue in
            if isOn != newValue { isOn = newValue }
        }
        .onChange(of: isOn) { _, newValue in
            if newValue != isSelected { selectionChanged(newValue) }
        }
        .accessibilityLabel(Text(descriptor.title))
        .accessibilityValue(Text(isSelected ? "Shown on dashboard" : "Hidden from dashboard"))
        .accessibilityHint(Text(accessibilityHint))
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
