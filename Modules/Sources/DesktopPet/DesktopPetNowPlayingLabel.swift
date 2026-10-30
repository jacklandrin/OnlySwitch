import AppKit
import Design
import SwiftUI

struct DesktopPetNowPlayingLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let nowPlaying: DesktopPetNowPlaying?

    var body: some View {
        ZStack {
            if let nowPlaying {
                content(nowPlaying)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: nowPlaying)
    }

    private func content(_ nowPlaying: DesktopPetNowPlaying) -> some View {
        VStack(spacing: 1) {
            line(nowPlaying.title, style: .title)
            if let subtitle = nowPlaying.subtitle {
                line(subtitle, style: .subtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesktopPetMetrics.nowPlayingHorizontalPadding)
        .frame(
            maxWidth: DesktopPetMetrics.nowPlayingSize.width,
            minHeight: DesktopPetMetrics.nowPlayingSize.height
        )
        .fixedSize(horizontal: false, vertical: true)
        .modifier(DesktopPetNowPlayingBackground())
        .help([nowPlaying.title, nowPlaying.subtitle].compactMap(\.self).joined(separator: "\n"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Desktop pet Now playing", bundle: .main))
        .accessibilityValue(
            [nowPlaying.title, nowPlaying.subtitle].compactMap(\.self).joined(separator: ", ")
        )
    }

    @ViewBuilder
    private func line(_ text: String, style: DesktopPetNowPlayingLine) -> some View {
        if style.scrolls(text, reduceMotion: reduceMotion) {
            RollingText(
                text: text,
                font: style.font,
                leftFade: DesktopPetNowPlayingLine.fade,
                rightFade: DesktopPetNowPlayingLine.fade,
                startDelay: 2
            )
            .frame(width: DesktopPetNowPlayingLine.width)
            // RollingText keeps scrolling once started, so restart it for each new text.
            .id(text)
        } else {
            Text(text)
                .font(Font(style.font))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

enum DesktopPetNowPlayingLine {
    case title
    case subtitle

    static let fade: CGFloat = 6
    static let width = DesktopPetMetrics.nowPlayingSize.width
        - DesktopPetMetrics.nowPlayingHorizontalPadding * 2

    var font: NSFont {
        let size: CGFloat = self == .title ? 11 : 10
        let font = NSFont.systemFont(ofSize: size, weight: self == .title ? .semibold : .regular)
        return font.fontDescriptor.withDesign(.rounded).flatMap {
            NSFont(descriptor: $0, size: size)
        } ?? font
    }

    /// Text that does not fit scrolls, unless Reduce Motion asks for a still, truncated line.
    func scrolls(_ text: String, reduceMotion: Bool) -> Bool {
        !reduceMotion && (text as NSString).size(withAttributes: [.font: font]).width > Self.width
    }
}

private struct DesktopPetNowPlayingBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
