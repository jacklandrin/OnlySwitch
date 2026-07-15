import RemoteCore
import SwiftUI

struct ControlTileView: View {
    let descriptor: RemoteControlDescriptor
    let status: DashboardFeature.TileStatus?
    let macName: String
    let isRequestInFlight: Bool
    let isEnabled: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    controlIcon
                        .font(.title2)
                        .frame(width: 34, height: 34)
                        .foregroundStyle(iconColor)
                    Spacer(minLength: 8)
                    if isRequestInFlight || status?.value.isProcessing == true {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Working")
                    } else if descriptor.behavior != .button, let isOn = status?.value.isOn {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let information = status?.value.secondaryInformation, information.isEmpty == false {
                        Text(information)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let reason = unavailableReason {
                        Label(reason, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else if status?.isStale == true {
                        Text("Last known status")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .padding(16)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || unavailableReason != nil ? 1 : 0.65)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isRequestInFlight)
        .accessibilityLabel("\(macName), \(descriptor.title)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder
    private var controlIcon: some View {
        switch descriptor.icon {
        case let .systemSymbol(name):
            Image(systemName: name)
        case let .png(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "switch.2")
            }
        }
    }

    private var unavailableReason: String? {
        if descriptor.isAvailable == false {
            return descriptor.unavailableReason ?? String(localized: "Unavailable on this Mac")
        }
        if status?.value.isAvailable == false {
            return status?.value.unavailableReason ?? String(localized: "Unavailable on this Mac")
        }
        return nil
    }

    private var accessibilityValue: String {
        if let unavailableReason { return String(localized: "Unavailable: \(unavailableReason)") }
        if status?.isStale == true { return String(localized: "Offline, showing last known status") }
        if isRequestInFlight { return String(localized: "Working") }
        if let isOn = status?.value.isOn { return isOn ? String(localized: "On") : String(localized: "Off") }
        return String(localized: "Ready")
    }

    private var accessibilityHint: String {
        if let unavailableReason { return unavailableReason }
        if isEnabled == false { return String(localized: "Connect to this Mac to use this control") }
        return descriptor.isDestructive
            ? String(localized: "Requires confirmation before running")
            : String(localized: "Runs this control on the selected Mac")
    }

    private var iconColor: Color {
        status?.value.isOn == true ? .accentColor : .primary
    }

    private var backgroundStyle: Color {
        status?.value.isOn == true ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground)
    }

    private var borderColor: Color {
        status?.value.isOn == true ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18)
    }
}
