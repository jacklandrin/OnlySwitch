import SwiftUI

struct BrowserEmptyView: View {
    let onManageBookmarks: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(BrowserStrings.text("Browser Empty Title"), systemImage: "safari")
        } description: {
            Text(BrowserStrings.text("Browser Empty Message"))
        } actions: {
            Button(BrowserStrings.text("Browser Manage Bookmarks"), action: onManageBookmarks)
                .buttonStyle(.borderedProminent)
        }
    }
}
