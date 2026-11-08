import RemoteCore
import SwiftUI

struct ControlTileView: View {
    static let iconSize: CGFloat = 28

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let descriptor: RemoteControlDescriptor
    let presentation: ControlTilePresentation
    let macName: String
    let isEnabled: Bool
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                headerLayout {
                    ControlTileIconView(
                        icon: descriptor.icon,
                        isShortcut: descriptor.id.kind == .shortcut,
                        tint: iconColor
                    )
                    ControlTileStatusBadge(
                        presentation: presentation,
                        reduceMotion: reduceMotion
                    )
                    .frame(maxWidth: .infinity, alignment: headerBadgeAlignment)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.localizedTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let information = presentation.secondaryInformation,
                       information.isEmpty == false {
                        Text(information)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let reason = presentation.unavailableReason {
                        Label(reason, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .modifier(
                ControlTileSurface(
                    tint: surfaceTint,
                    borderColor: borderColor,
                    isInteractive: isEnabled
                )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .hoverEffect(.highlight)
        .focusable(isEnabled)
        .disabled(!isEnabled)
        .animation(presentationAnimation, value: presentation.visualState)
        .accessibilityLabel("\(macName), \(descriptor.localizedTitle)")
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityInputLabels([LocalizedStringKey(descriptor.localizedTitle)])
    }

    private var accessibilityHint: String {
        if let unavailableReason = presentation.unavailableReason { return unavailableReason }
        if presentation.visualState == .pending { return String(localized: "Working") }
        if isEnabled == false { return String(localized: "Connect to this Mac to use this control") }
        return descriptor.isDestructive
            ? String(localized: "Requires confirmation before running")
            : String(localized: "Runs this control on the selected Mac")
    }

    private var headerLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        } else {
            AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        }
    }

    private var headerBadgeAlignment: Alignment {
        dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
    }

    private var iconColor: Color {
        presentation.lastKnownIsOn == true ? .accentColor : .primary
    }

    private var presentationAnimation: Animation? {
        guard reduceMotion == false else { return nil }
        switch presentation.visualState {
        case .on, .off, .ready:
            return .snappy(duration: 0.28)
        case .pending, .stale, .offline, .unavailable, .failed:
            return nil
        }
    }

    private var surfaceTint: Color {
        switch presentation.visualState {
        case .on, .pending:
            .accentColor
        case .off, .ready, .stale:
            .secondary
        case .offline:
            .orange
        case .unavailable, .failed:
            .red
        }
    }

    private var borderColor: Color {
        surfaceTint.opacity(presentation.visualState == .on ? 0.38 : 0.24)
    }
}

private struct ControlTileSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let tint: Color
    let borderColor: Color
    let isInteractive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(tint.opacity(0.10), in: tileShape)
                .background(opaqueSurfaceColor, in: tileShape)
                .overlay { border }
        } else if #available(iOS 26, *) {
            content
                .background(tint.opacity(0.06), in: tileShape)
                .overlay { border }
                .glassEffect(
                    .regular.tint(tint.opacity(0.18)).interactive(isInteractive),
                    in: .rect(cornerRadius: 22)
                )
        } else {
            content
                .background(tint.opacity(0.10), in: tileShape)
                .background(.thinMaterial, in: tileShape)
                .overlay { border }
        }
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22)
    }

    private var border: some View {
        tileShape.strokeBorder(
            colorSchemeContrast == .increased ? Color.primary.opacity(0.42) : borderColor,
            lineWidth: colorSchemeContrast == .increased ? 2 : 1
        )
    }

    private var opaqueSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.13)
            : .white
    }
}
