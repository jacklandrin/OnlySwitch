import AppKit
import ComposableArchitecture
import Extensions
import SwiftUI

struct DockPreviewView: View {
    static let renderingInset: CGFloat = 16
    static let mediaControlsHeight: CGFloat = 40

    let store: StoreOf<DockPreviewFeature>

    var body: some View {
        WithPerceptionTracking {
            if let preview = store.preview {
                VStack(alignment: .leading, spacing: 0) {
                    if preview.windows.isEmpty {
                        if store.status == .captureFailed {
                            Text("Window preview unavailable".localized())
                                .padding(16)
                        }
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(preview.windows) { window in
                                    Button {
                                        store.send(.windowTapped(window.id))
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            thumbnail(for: window)
                                                .frame(width: 180, height: 112)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            Text(window.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(width: 180)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!window.isActivatable)
                                    .accessibilityLabel("\(preview.appName), \(window.title)")
                                }
                            }
                            .padding(12)
                            .frame(maxHeight: .infinity)
                        }
                        .scrollIndicators(.hidden)
                        if store.status == .activationFailed {
                            Text("Unable to activate window".localized())
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
                    if preview.mediaPlayer != nil {
                        mediaControls(for: preview)
                            .frame(maxHeight: preview.windows.isEmpty && store.status != .captureFailed
                                   ? .infinity : Self.mediaControlsHeight)
                    }
                }
                .background {
                    if #available(macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.clear)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.regularMaterial)
                    }
                }
                .onExitCommand { store.send(.escapePressed) }
                .onHover { hovering in
                    if !hovering { store.send(.pointerExited) }
                }
                // Leave room for the glass edge outside the card's layout bounds.
                .padding(Self.renderingInset)
            }
        }
    }

    private func mediaControls(for preview: DockPreviewFeature.State.Preview) -> some View {
        HStack(spacing: 20) {
            mediaButton(.previousTrack, title: "Previous Track", systemImage: "backward.fill", appName: preview.appName)
            mediaButton(
                .playPause,
                title: preview.isMediaPlaying ? "Pause" : "Play",
                systemImage: preview.isMediaPlaying ? "pause.fill" : "play.fill",
                appName: preview.appName
            )
            mediaButton(.nextTrack, title: "Next Track", systemImage: "forward.fill", appName: preview.appName)
        }
        .frame(maxWidth: .infinity)
    }

    private func mediaButton(
        _ command: DockPreviewMediaCommand,
        title: String,
        systemImage: String,
        appName: String
    ) -> some View {
        Button {
            store.send(.mediaCommandTapped(command))
        } label: {
            Label(title.localized(), systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title.localized())
        .accessibilityLabel("\(appName), \(title.localized())")
    }

    @ViewBuilder
    private func thumbnail(for window: DockPreviewWindow) -> some View {
        if let data = window.thumbnailData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
                .accessibilityHidden(true)
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "macwindow")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("Window preview unavailable".localized()))
        }
    }
}
