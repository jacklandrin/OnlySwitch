import SwiftUI

struct DesktopPetPlaybackControls: View {
    let isPlaying: Bool
    let onPlayPause: @MainActor () -> Void
    let onNext: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 6) {
            DesktopPetPlaybackButton(
                title: isPlaying
                    ? String(localized: "Desktop pet Pause", bundle: .main)
                    : String(localized: "Desktop pet Play", bundle: .main),
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                showsTitle: false,
                action: onPlayPause
            )
            DesktopPetPlaybackButton(
                title: String(localized: "Desktop pet Next", bundle: .main),
                systemImage: "forward.end.fill",
                action: onNext
            )
        }
    }
}
