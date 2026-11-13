import ComposableArchitecture
import SwiftUI

/// Settings → Browser: manage bookmarks and clear the browser's website data.
public struct BrowserSettingsView: View {
    let store: StoreOf<BrowserFeature>
    @State private var confirmsClear = false

    public init(store: StoreOf<BrowserFeature>) {
        self.store = store
    }

    public var body: some View {
        Form {
            if store.storageCorrupted {
                Label(BrowserStrings.text("Browser Storage Corrupted"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Section {
                if store.bookmarks.isEmpty {
                    Text(BrowserStrings.text("Browser Settings Empty"))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.bookmarks) { bookmark in
                    row(bookmark)
                }
                .onMove { store.send(.moveBookmarks($0, $1)) }
            } header: {
                HStack {
                    Text(BrowserStrings.text("Browser Bookmarks"))
                    Spacer()
                    Button(BrowserStrings.text("Browser Add Bookmark"), systemImage: "plus") {
                        store.send(.addBookmarkTapped)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section(BrowserStrings.text("Browser Website Data")) {
                Text(BrowserStrings.text("Browser Website Data Note"))
                    .foregroundStyle(.secondary)
                Button(BrowserStrings.text("Browser Clear Website Data"), role: .destructive) {
                    confirmsClear = true
                }
                .disabled(store.isClearingWebsiteData)
            }
        }
        .formStyle(.grouped)
        .onAppear { store.send(.onAppear) }
        .sheet(isPresented: Binding(
            get: { store.draft != nil },
            set: { if !$0 { store.send(.draftCancelTapped) } }
        )) {
            if let draft = store.draft {
                BrowserBookmarkEditor(store: store, draft: draft)
            }
        }
        .confirmationDialog(BrowserStrings.text("Browser Clear Website Data Title"), isPresented: $confirmsClear) {
            Button(BrowserStrings.text("Browser Clear"), role: .destructive) { store.send(.clearWebsiteDataTapped) }
            Button(BrowserStrings.text("Browser Cancel"), role: .cancel) {}
        } message: {
            Text(BrowserStrings.text("Browser Clear Website Data Message"))
        }
    }

    private func row(_ bookmark: BrowserBookmark) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.displayTitle)
                Text(bookmark.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if bookmark.usesMobileUserAgent {
                Image(systemName: "iphone")
                    .foregroundStyle(.secondary)
                    .help(BrowserStrings.text("Browser Mobile Version"))
                    .accessibilityLabel(BrowserStrings.text("Browser Mobile Version"))
            }
            Button(BrowserStrings.text("Browser Edit Bookmark"), systemImage: "pencil") {
                store.send(.editBookmarkTapped(bookmark.id))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(BrowserStrings.text("Browser Edit Bookmark"))
            Button(BrowserStrings.text("Browser Delete Bookmark"), systemImage: "trash", role: .destructive) {
                store.send(.deleteBookmarkTapped(bookmark.id))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(BrowserStrings.text("Browser Delete Bookmark"))
        }
        .contextMenu {
            Button(BrowserStrings.text("Browser Edit Bookmark")) { store.send(.editBookmarkTapped(bookmark.id)) }
            Button(BrowserStrings.text("Browser Delete Bookmark"), role: .destructive) {
                store.send(.deleteBookmarkTapped(bookmark.id))
            }
        }
    }
}
