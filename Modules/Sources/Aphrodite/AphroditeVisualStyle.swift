import CoreGraphics
#if os(macOS)
import SwiftUI
#endif

public enum AphroditeVisualStyle {
    public static let fallbackIconName = "star.hexagon"
    public static let minimumPreviewWidth: CGFloat = 240

    public struct CardMetrics: Equatable, Sendable {
        public let isCompact: Bool
        public let iconSize: CGFloat
        public let minimumHeight: CGFloat
        public let horizontalPadding: CGFloat
        public let actionSize: CGFloat
    }

    public static func cardMetrics(availableWidth: CGFloat) -> CardMetrics {
        let width = availableWidth.isFinite ? max(0, availableWidth) : 0
        let compact = width < 360
        return CardMetrics(
            isCompact: compact,
            iconSize: compact ? 28 : 34,
            minimumHeight: compact ? 52 : 60,
            horizontalPadding: compact ? 10 : 14,
            actionSize: 32
        )
    }
}

#if os(macOS)
@available(macOS 26.0, *)
public struct AphroditeSectionHeader: View {
    private let title: String
    private let systemImage: String
    private let detail: String?

    public init(_ title: String, systemImage: String, detail: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@available(macOS 26.0, *)
public struct AphroditeLibraryCard<Actions: View>: View {
    private let app: AphroditeApp
    private let isSelected: Bool
    private let isOpenDisabled: Bool
    private let open: () -> Void
    private let actions: Actions

    public init(
        app: AphroditeApp,
        isSelected: Bool = false,
        isOpenDisabled: Bool = false,
        open: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.app = app
        self.isSelected = isSelected
        self.isOpenDisabled = isOpenDisabled
        self.open = open
        self.actions = actions()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            content(isCompact: false)
            content(isCompact: true)
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func content(isCompact: Bool) -> some View {
        let metrics = AphroditeVisualStyle.cardMetrics(availableWidth: isCompact ? 320 : 800)
        return HStack(spacing: isCompact ? 8 : 12) {
            Button(action: open) {
                HStack(spacing: isCompact ? 8 : 12) {
                    AphroditeIconView(svg: app.iconSVG, fallbackSystemImage: AphroditeVisualStyle.fallbackIconName)
                        .frame(width: metrics.iconSize, height: metrics.iconSize)
                    Text(app.title)
                        .font(.body)
                        .bold()
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isOpenDisabled)
            .accessibilityLabel(app.title)
            actions
                .controlSize(isCompact ? .small : .regular)
                .frame(minWidth: metrics.actionSize, minHeight: metrics.actionSize)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(minHeight: metrics.minimumHeight)
    }
}

@available(macOS 26.0, *)
public struct AphroditePanelSurface: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

@available(macOS 26.0, *)
public extension View {
    func aphroditePanelSurface() -> some View {
        modifier(AphroditePanelSurface())
    }
}
#endif
