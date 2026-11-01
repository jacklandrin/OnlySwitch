import ComposableArchitecture
import RemoteCore
import SwiftUI

/// One grid cell: thumbnail, date and pinned/copied state. Tap opens the viewer; Copy and Delete are
/// in the context menu and exposed as accessibility actions. Dragging hands out the original.
struct RemoteScreenshotCell: View {
    let store: StoreOf<RemoteScreenshotsFeature>
    let item: RemoteScreenshotItem

    var body: some View {
        let isDeleting = store.state.isDeleting(item.id)
        let isDownloading = store.state.isDownloading(item.id)
        let isCopied = store.copiedItemID == item.id
        Button(action: open) {
            RemoteSystemMonitorCardSurface(padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    RemoteScreenshotThumbnailView(
                        url: store.thumbnailURLs[item.id],
                        isLoading: store.loadingThumbnailIDs.contains(item.id)
                    )
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        if item.isPinned {
                            RemoteScreenshotBadge(systemImage: "pin.fill")
                        }
                    }
                    .overlay {
                        if isDeleting || isDownloading {
                            ProgressView()
                                .padding(10)
                                .background(.thinMaterial, in: Circle())
                        }
                    }
                    HStack(spacing: 6) {
                        Text(item.createdAt, format: RemoteScreenshotCell.dateFormat)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if isCopied {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .opacity(isDeleting ? 0.5 : 1)
        .disabled(isDeleting)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc", action: copy)
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                .disabled(store.canDelete == false)
        }
        .onDrag(dragProvider)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isCopied ? Text("Copied") : Text(verbatim: ""))
        .accessibilityHint("Opens the screenshot")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityActions {
            Button("Copy", action: copy)
            if store.canDelete {
                Button("Delete", action: delete)
            }
        }
    }

    static let dateFormat = Date.FormatStyle.dateTime.month().day().hour().minute()

    private var accessibilityLabel: Text {
        let date = item.createdAt.formatted(RemoteScreenshotCell.dateFormat)
        return item.isPinned ? Text("Pinned screenshot, \(date)") : Text("Screenshot, \(date)")
    }

    private func open() { store.send(.itemTapped(item.id)) }
    private func copy() { store.send(.copyTapped(item.id)) }
    private func delete() { store.send(.deleteTapped(item.id)) }

    private func dragProvider() -> NSItemProvider {
        guard let macID = store.selectedMacID else { return NSItemProvider() }
        let provider = RemoteScreenshotDragProvider.itemProvider(macID: macID, item: item, cachedURL: store.imageURLs[item.id], images: store.dragImages.client)
        // Start the download now: on iPhone the drop target asks for the file after OnlyRemote has
        // left the foreground. The provider then joins the same single-flight load.
        store.send(.dragStarted(item.id))
        return provider
    }
}
