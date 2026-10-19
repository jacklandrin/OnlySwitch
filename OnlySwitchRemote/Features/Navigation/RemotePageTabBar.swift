import SwiftUI

struct RemotePageTabBar: View {
    // Keep the control at the standard compact-control height. The requested
    // compactness is horizontal: the bar floats at a bounded width instead of
    // reducing the height of its controls.
    static let visualHeight: CGFloat = 44
    static let minimumTouchHeight: CGFloat = 44
    static let contentBottomInset = minimumTouchHeight + 4
    static let maximumWidth: CGFloat = 390
    static let horizontalPadding: CGFloat = 16

    @Binding var selection: RemoteAppPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let count: CGFloat = 5
            let width = max(0, (proxy.size.width - spacing * (count - 1)) / count)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay { Capsule().stroke(Color.accentColor.opacity(0.45)) }
                    .frame(width: width, height: Self.visualHeight)
                    .offset(x: CGFloat(selection.index) * (width + spacing))
                    .accessibilityHidden(true)
                HStack(spacing: spacing) {
                    tabButton(.controls, title: "Controls", symbol: "switch.2")
                    tabButton(.systemMonitor, title: "System Monitor", symbol: "waveform.path.ecg")
                    tabButton(.codexUsage, title: "Codex Usage", imageName: RemoteCodexUsagePresentation.tabImageName)
                    tabButton(.claudeUsage, title: "Claude Usage", imageName: RemoteClaudeUsagePresentation.tabImageName)
                    tabButton(.aphrodite, title: "Aphrodite", symbol: "sparkles.rectangle.stack")
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selection)
        }
        .frame(height: Self.minimumTouchHeight)
        .background {
            Group {
                if reduceTransparency {
                    Capsule().fill(Color(.systemBackground))
                } else {
                    Capsule().fill(.regularMaterial)
                }
            }
            .frame(height: Self.visualHeight)
        }
        .overlay {
            Capsule().strokeBorder(
                Color.primary.opacity(contrast == .increased ? 0.35 : 0.10),
                lineWidth: contrast == .increased ? 2 : 1
            )
            .frame(height: Self.visualHeight)
        }
        .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
        .frame(maxWidth: Self.maximumWidth)
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity)
    }

    private func tabButton(_ page: RemoteAppPage, title: LocalizedStringKey, symbol: String) -> some View {
        tabButton(page, title: title) { Image(systemName: symbol) }
    }

    /// Tab with a template brand logo from the asset catalog, sized to match the SF Symbol tabs.
    private func tabButton(_ page: RemoteAppPage, title: LocalizedStringKey, imageName: String) -> some View {
        tabButton(page, title: title) {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        }
    }

    private func tabButton<Icon: View>(_ page: RemoteAppPage, title: LocalizedStringKey, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            selection = page
        } label: {
            Label { Text(title) } icon: { icon() }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(selection == page ? .primary : .secondary)
                .frame(maxWidth: .infinity, minHeight: Self.minimumTouchHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selection == page ? .isSelected : [])
        .accessibilityHint("Shows this page")
    }
}

private extension RemoteAppPage {
    var index: Int {
        switch self {
        case .controls: 0
        case .systemMonitor: 1
        case .codexUsage: 2
        case .claudeUsage: 3
        case .aphrodite: 4
        }
    }
}
