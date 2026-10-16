import AppKit
import ComposableArchitecture
import Extensions
import SwiftUI

struct DockPreviewView: View {
    let store: StoreOf<DockPreviewFeature>

    var body: some View {
        WithPerceptionTracking {
            if let preview = store.preview {
                VStack(alignment: .leading, spacing: 0) {
                    if preview.windows.isEmpty && store.status == .captureFailed {
                        Text("Window preview unavailable".localized())
                            .padding(16)
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
            }
        }
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
